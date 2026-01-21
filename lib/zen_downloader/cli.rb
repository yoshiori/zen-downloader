# frozen_string_literal: true

require "thor"

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

    default_task :version
  end
end
