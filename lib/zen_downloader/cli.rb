# frozen_string_literal: true

require "thor"
require "fileutils"
require "tty-progressbar"
require "unicode/display_width"

module ZenDownloader
  class CLI < Thor
    desc "version", "Show version"
    def version
      puts "zen-downloader #{VERSION}"
    end

    desc "login", "Login to Zen University"
    def login
      config = Config.new
      client = Client.new(config)
      client.login
      puts "Login successful!"
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    desc "fetch URL", "Fetch a ZEN Study page"
    def fetch(url)
      config = Config.new
      client = Client.new(config)
      page = client.fetch_page(url)
      puts "Title: #{page.title}"
      puts page.body
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    desc "list URL", "List videos in a chapter or course"
    def list(url)
      config = Config.new
      client = Client.new(config)

      parsed = parse_url(url)

      case parsed[:type]
      when :course
        list_course(client, parsed[:course_id])
      when :chapter
        list_chapter(client, parsed[:course_id], parsed[:chapter_id])
      end
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    desc "verify", "Verify session status and cookie persistence"
    def verify
      config = Config.new
      client = Client.new(config)

      puts "Checking session validity..."
      valid = client.send(:session_valid?)
      puts "Session valid: #{valid}"

      if valid
        puts "\nSession is valid. No login needed."
      else
        puts "\nSession is invalid. Checking cookies in browser..."
        cookies = client.instance_variable_get(:@browser)&.cookies&.all || {}
        puts "Cookies in memory: #{cookies.keys}"
        auth_cookies = cookies.select { |name, _| name.to_s.include?("auth") || name.to_s.include?("session") || name.to_s.include?("zane") }
        puts "Auth cookies: #{auth_cookies.keys}"
      end
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    desc "download URL", "Download all videos from a chapter or course"
    option :output, aliases: "-o", desc: "Output directory"
    option :parallel, aliases: "-p", type: :numeric, default: 6, desc: "Number of parallel downloads"
    def download(url)
      config = Config.new
      client = Client.new(config)

      parsed = parse_url(url)
      output_dir = options[:output] || config.download_dir
      output_dir = File.expand_path(output_dir)
      parallel_count = options[:parallel]

      case parsed[:type]
      when :course
        download_course(client, parsed[:course_id], output_dir, parallel_count)
      when :chapter
        download_chapter(client, parsed[:course_id], parsed[:chapter_id], output_dir, parallel_count)
      end
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    default_task :version

    private

    def parse_url(url)
      if (match = url.match(%r{/courses/(\d+)/chapters/(\d+)}))
        { type: :chapter, course_id: match[1], chapter_id: match[2] }
      elsif (match = url.match(%r{/courses/(\d+)}))
        { type: :course, course_id: match[1] }
      else
        raise Error, "Invalid URL: #{url}"
      end
    end

    def list_course(client, course_id)
      course = client.fetch_course(course_id)

      puts "Course: #{course.title}"
      puts "=" * 50
      course.chapters.each_with_index do |chapter, i|
        puts "#{i + 1}. #{chapter.title}"
        puts "   ID: #{chapter.id}"
      end
    end

    def list_chapter(client, course_id, chapter_id)
      chapter = client.fetch_chapter(course_id, chapter_id)

      puts "Course: #{chapter.course_title}"
      puts "Chapter: #{chapter.title}"
      puts "=" * 50
      chapter.movies.each_with_index do |movie, i|
        puts "#{i + 1}. #{movie.title} (#{movie.formatted_length})"
        puts "   ID: #{movie.id}"
      end
    end

    def download_course(client, course_id, output_dir, parallel_count)
      course = client.fetch_course(course_id)

      puts "Course: #{course.title}"
      puts "Chapters: #{course.chapters.length}"
      puts "Output: #{output_dir}"
      puts "Parallel: #{parallel_count}"
      puts "=" * 50

      course.chapters.each_with_index do |chapter_info, i|
        puts "\n[Chapter #{i + 1}/#{course.chapters.length}] #{chapter_info.title}"
        puts "-" * 50
        download_chapter(client, course_id, chapter_info.id, output_dir, parallel_count)
      end

      puts "\nAll chapters completed!"
    end

    def download_chapter(client, course_id, chapter_id, output_dir, parallel_count)
      chapter = client.fetch_chapter(course_id, chapter_id)

      # Create directory structure: output_dir/course_title/chapter_title
      course_dir = File.join(output_dir, sanitize_filename(chapter.course_title))
      chapter_dir = File.join(course_dir, sanitize_filename(chapter.title))
      FileUtils.mkdir_p(chapter_dir)

      puts "Chapter: #{chapter.title}"
      puts "Output: #{chapter_dir}"

      # Prepare download tasks
      tasks = []
      chapter.movies.each_with_index do |movie, i|
        movie_info = client.fetch_movie_info(course_id, chapter_id, movie.id)

        unless movie_info.hls_url
          puts "[#{i + 1}/#{chapter.movies.length}] #{movie.title} - No HLS URL, skipping..."
          next
        end

        filename = format("%02d_%s.mp4", i + 1, sanitize_filename(movie.title))
        output_path = File.join(chapter_dir, filename)

        if File.exist?(output_path)
          puts "[#{i + 1}/#{chapter.movies.length}] #{movie.title} - Already exists, skipping..."
          next
        end

        tasks << {
          index: i + 1,
          total: chapter.movies.length,
          title: movie.title,
          hls_url: movie_info.hls_url,
          output_path: output_path,
          filename: filename,
          duration: movie_info.length || 0
        }
      end

      if tasks.empty?
        puts "No videos to download."
      else
        puts "Downloading #{tasks.length} videos..."
        download_parallel(tasks, parallel_count)
        puts "Downloads completed!"
      end
    end

    def sanitize_filename(name)
      name.gsub(/[\/\\:*?"<>|]/, "_").gsub(/\s+/, "_")
    end

    def download_parallel(tasks, parallel_count)
      multi = TTY::ProgressBar::Multi.new("[:bar] :current/:total", width: 40, output: $stdout)

      # Find the longest title for alignment (using display width for CJK characters)
      max_display_width = tasks.map { |t| Unicode::DisplayWidth.of(truncate_title(t[:title], 25)) }.max

      # Create progress bars for each task (sorted by index)
      bars = {}
      tasks.sort_by { |t| t[:index] }.each do |task|
        label = pad_to_width(truncate_title(task[:title], 25), max_display_width)
        total = task[:duration] > 0 ? task[:duration] : 100
        bar = multi.register("[#{task[:index]}/#{task[:total]}] #{label} [:bar] :percent",
                             total: total,
                             width: 15,
                             complete: "█",
                             incomplete: "░",
                             output: $stdout)
        bar.start  # Start all bars upfront to fix display order
        bars[task[:index]] = { bar: bar, task: task }
      end

      queue = Queue.new
      tasks.each { |task| queue << task }

      errors = []
      mutex = Mutex.new

      threads = parallel_count.times.map do
        Thread.new do
          while (task = queue.pop(true) rescue nil)
            bar_info = bars[task[:index]]
            bar = bar_info[:bar]

            begin
              download_with_progress(task[:hls_url], task[:output_path], task[:duration]) do |progress|
                bar.current = progress
              end
              bar.current = bar.total
              bar.finish
            rescue StandardError => e
              mutex.synchronize do
                errors << { task: task, error: e }
              end
              bar.finish
            end
          end
        end
      end

      threads.each(&:join)

      puts ""
      unless errors.empty?
        puts "Failed downloads:"
        errors.each do |err|
          puts "  - #{err[:task][:filename]}: #{err[:error].message}"
        end
      end
    end

    def truncate_title(title, max_length)
      return title if title.length <= max_length

      title[0, max_length - 3] + "..."
    end

    def pad_to_width(str, target_width)
      current_width = Unicode::DisplayWidth.of(str)
      padding = target_width - current_width
      padding > 0 ? str + (" " * padding) : str
    end

    def download_with_progress(hls_url, output_path, duration)
      temp_path = "/tmp/zen_download_#{Process.pid}_#{Thread.current.object_id}_#{Time.now.to_i}.mp4"
      progress_path = "/tmp/zen_progress_#{Process.pid}_#{Thread.current.object_id}_#{Time.now.to_i}.txt"

      cmd = [
        "ffmpeg",
        "-i", hls_url,
        "-c", "copy",
        "-bsf:a", "aac_adtstoasc",
        "-y",
        "-loglevel", "error",
        "-progress", progress_path,
        temp_path
      ]

      pid = spawn(*cmd, out: File::NULL, err: File::NULL)
      done = false

      # Monitor progress in background
      monitor_thread = Thread.new do
        last_time = 0
        until done
          if File.exist?(progress_path)
            content = File.read(progress_path) rescue ""
            # Find the last valid out_time_ms value (not N/A)
            matches = content.scan(/out_time_ms=(\d+)/)
            if matches.any?
              current_us = matches.last[0].to_i
              current_sec = current_us / 1_000_000
              if duration > 0 && current_sec != last_time
                yield [current_sec, duration].min
                last_time = current_sec
              end
            end
          end
          sleep 0.2
        end
      end

      _, status = Process.wait2(pid)
      done = true
      monitor_thread.join

      FileUtils.rm_f(progress_path)

      unless status.success?
        raise Error, "ffmpeg failed (exit code: #{status.exitstatus})"
      end

      FileUtils.mv(temp_path, output_path)
    rescue StandardError => e
      done = true
      FileUtils.rm_f(temp_path)
      FileUtils.rm_f(progress_path)
      raise e
    end

    def download_hls(hls_url, output_path)
      # Use a temp file with ASCII name to avoid ffmpeg issues with Japanese filenames
      temp_path = "/tmp/zen_download_#{Process.pid}_#{Time.now.to_i}.mp4"

      cmd = [
        "ffmpeg",
        "-i", hls_url,
        "-c", "copy",
        "-bsf:a", "aac_adtstoasc",
        "-y",
        "-loglevel", "error",
        "-stats",
        temp_path
      ]

      result = system(*cmd)

      unless result
        raise Error, "ffmpeg failed to download video (exit code: #{$?.exitstatus})"
      end

      FileUtils.mv(temp_path, output_path)
    rescue StandardError => e
      FileUtils.rm_f(temp_path)
      raise e
    end
  end
end
