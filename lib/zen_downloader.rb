# frozen_string_literal: true

require_relative "zen_downloader/version"
require_relative "zen_downloader/config"
require_relative "zen_downloader/client"
require_relative "zen_downloader/cli"

module ZenDownloader
  class Error < StandardError; end
  class AuthenticationError < Error; end
end
