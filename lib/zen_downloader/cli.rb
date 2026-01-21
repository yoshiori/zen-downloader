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

    desc "login URL", "Test login to Zen University with a target URL"
    def login(url)
      config = Config.new
      client = Client.new(config)
      client.login(url)
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

    desc "list URL", "List videos in a chapter"
    def list(url)
      config = Config.new
      client = Client.new(config)

      course_id, chapter_id = parse_chapter_url(url)
      chapter = client.fetch_chapter(course_id, chapter_id)

      puts "Course: #{chapter.course_title}"
      puts "Chapter: #{chapter.title}"
      puts "=" * 50
      chapter.movies.each_with_index do |movie, i|
        puts "#{i + 1}. #{movie.title} (#{movie.formatted_length})"
        puts "   ID: #{movie.id}"
      end
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    desc "download URL", "Download all videos from a chapter"
    option :output, aliases: "-o", desc: "Output directory"
    option :parallel, aliases: "-p", type: :numeric, default: 6, desc: "Number of parallel downloads"
    def download(url)
      config = Config.new
      client = Client.new(config)

      course_id, chapter_id = parse_chapter_url(url)
      chapter = client.fetch_chapter(course_id, chapter_id)

      output_dir = options[:output] || config.download_dir
      output_dir = File.expand_path(output_dir)
      parallel_count = options[:parallel]

      # Create directory structure: output_dir/course_title/chapter_title
      course_dir = File.join(output_dir, sanitize_filename(chapter.course_title))
      chapter_dir = File.join(course_dir, sanitize_filename(chapter.title))
      FileUtils.mkdir_p(chapter_dir)

      puts "Course: #{chapter.course_title}"
      puts "Chapter: #{chapter.title}"
      puts "Output: #{chapter_dir}"
      puts "Parallel: #{parallel_count}"
      puts "=" * 50

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
        puts "\nNo videos to download."
      else
        puts "\nDownloading #{tasks.length} videos..."
        download_parallel(tasks, parallel_count)
        puts "\nAll downloads completed!"
      end
    rescue Error => e
      puts "Error: #{e.message}"
      exit 1
    ensure
      client&.quit
    end

    default_task :version

    private

    def parse_chapter_url(url)
      match = url.match(%r{/courses/(\d+)/chapters/(\d+)})
      raise Error, "Invalid chapter URL: #{url}" unless match

      [match[1], match[2]]
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
