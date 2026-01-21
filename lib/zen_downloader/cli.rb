# frozen_string_literal: true

require "thor"
require "fileutils"

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
    def download(url)
      config = Config.new
      client = Client.new(config)

      course_id, chapter_id = parse_chapter_url(url)
      chapter = client.fetch_chapter(course_id, chapter_id)

      output_dir = options[:output] || config.download_dir
      output_dir = File.expand_path(output_dir)

      # Create directory structure: output_dir/course_title/chapter_title
      course_dir = File.join(output_dir, sanitize_filename(chapter.course_title))
      chapter_dir = File.join(course_dir, sanitize_filename(chapter.title))
      FileUtils.mkdir_p(chapter_dir)

      puts "Course: #{chapter.course_title}"
      puts "Chapter: #{chapter.title}"
      puts "Output: #{chapter_dir}"
      puts "=" * 50

      chapter.movies.each_with_index do |movie, i|
        puts "\n[#{i + 1}/#{chapter.movies.length}] #{movie.title}"

        movie_info = client.fetch_movie_info(course_id, chapter_id, movie.id)

        unless movie_info.hls_url
          puts "  No HLS URL available, skipping..."
          next
        end

        filename = format("%02d_%s.mp4", i + 1, sanitize_filename(movie.title))
        output_path = File.join(chapter_dir, filename)

        if File.exist?(output_path)
          puts "  Already exists, skipping..."
          next
        end

        puts "  Downloading..."
        download_hls(movie_info.hls_url, output_path)
        puts "  Done: #{filename}"
      end

      puts "\nAll downloads completed!"
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
