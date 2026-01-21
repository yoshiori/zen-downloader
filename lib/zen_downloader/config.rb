# frozen_string_literal: true

require "yaml"

module ZenDownloader
  class Config
    DEFAULT_CONFIG_PATH = File.expand_path("~/.zen-downloader.yml")

    attr_reader :username, :password, :download_dir

    def initialize(path = DEFAULT_CONFIG_PATH)
      @path = path
      load_config
    end

    private

    def load_config
      unless File.exist?(@path)
        raise Error, "Config file not found: #{@path}\nPlease create it with your credentials."
      end

      config = YAML.load_file(@path)
      @username = config["username"]
      @password = config["password"]
      @download_dir = config["download_dir"] || "."

      validate!
    end

    def validate!
      raise Error, "username is required in config" if @username.nil? || @username.empty?
      raise Error, "password is required in config" if @password.nil? || @password.empty?
    end
  end
end
