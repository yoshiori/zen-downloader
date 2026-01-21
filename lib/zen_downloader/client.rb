# frozen_string_literal: true

require "ferrum"

module ZenDownloader
  class Client
    BASE_URL = "https://www.nnn.ed.nico"

    def initialize(config)
      @config = config
      @browser = nil
      @logged_in = false
    end

    def login(target_url)
      start_browser

      # Step 1: Access target URL (will show login selection)
      @browser.go_to(target_url)
      wait_for_page_load

      # Step 2: Find and click ZEN ID login link
      zen_link = @browser.at_css('a[href*="target_type=zen_id"]')
      raise Error, "ZEN ID login link not found" unless zen_link

      zen_link.click
      wait_for_page_load

      # Step 3: Submit email (first step of Auth0 Universal Login)
      email_field = wait_for_element('input[type="email"], input[name="username"]')
      raise Error, "Email field not found" unless email_field

      email_field.focus.type(@config.username)
      submit_button = @browser.at_css('button[type="submit"]')
      submit_button.click
      wait_for_page_load

      # Step 4: Submit password (second step)
      password_field = wait_for_element('input[type="password"], input[name="password"]')
      raise Error, "Password field not found" unless password_field

      password_field.focus.type(@config.password)
      submit_button = @browser.at_css('button[type="submit"]')
      submit_button.click
      wait_for_page_load

      # Check for authentication error
      check_authentication_error

      # Step 5: Login successful
      @logged_in = true
      current_page
    end

    def fetch_page(url)
      return get_page(url) if logged_in?

      login(url)
    end

    def logged_in?
      @logged_in
    end

    def quit
      @browser&.quit
      @browser = nil
    end

    def current_page
      PageWrapper.new(@browser)
    end

    private

    def start_browser
      return if @browser

      @browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080]
      )
    end

    def get_page(url)
      start_browser
      @browser.go_to(url)
      wait_for_page_load
      current_page
    end

    def wait_for_page_load
      sleep 0.5
      @browser.network.wait_for_idle(timeout: 10)
    rescue Ferrum::TimeoutError
      # Continue even if network doesn't fully idle
    end

    def wait_for_element(selector, timeout: 10)
      start_time = Time.now
      loop do
        element = @browser.at_css(selector)
        return element if element

        raise Error, "Element not found: #{selector}" if Time.now - start_time > timeout

        sleep 0.2
      end
    end

    def check_authentication_error
      error_element = @browser.at_css("#error-element-password, .ulp-input-error-message, .error-message")
      return unless error_element

      error_message = error_element.text.strip
      raise AuthenticationError, error_message unless error_message.empty?
    end
  end

  class PageWrapper
    def initialize(browser)
      @browser = browser
    end

    def title
      @browser.at_css("title")&.text
    end

    def body
      @browser.body
    end

    def url
      @browser.current_url
    end
  end
end
