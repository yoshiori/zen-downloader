# frozen_string_literal: true

require "ferrum"
require "fileutils"
require "json"

module ZenDownloader
  class Client
    BASE_URL = "https://www.nnn.ed.nico"
    API_URL = "https://api.nnn.ed.nico"

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

    def fetch_course(course_id)
      ensure_logged_in_for_course(course_id)

      data = fetch_api("/v2/material/courses/#{course_id}?revision=1")
      Course.new(data)
    end

    def fetch_chapter(course_id, chapter_id)
      ensure_logged_in(course_id, chapter_id)

      # Fetch course info to get course title
      course_data = fetch_api("/v2/material/courses/#{course_id}?revision=1")
      course = course_data["course"]

      # Use subject_category title (e.g., "法学Ⅰ") as the main course name
      course_title = course.dig("subject_category", "title") || course["title"]

      data = fetch_api("/v2/material/courses/#{course_id}/chapters/#{chapter_id}?revision=1")
      Chapter.new(data, course_id, course_title)
    end

    def fetch_movie_info(course_id, chapter_id, movie_id)
      ensure_logged_in(course_id, chapter_id)

      data = fetch_api("/v2/material/courses/#{course_id}/chapters/#{chapter_id}/movies/#{movie_id}?revision=1")
      MovieInfo.new(data)
    end

    def logged_in?
      @logged_in
    end

    def quit
      if @browser
        save_cookies
        @browser.quit
      end
      @browser = nil
    end

    def save_cookies
      return unless @browser

      cookies = @browser.cookies.all.values.map(&:to_h)
      File.write(cookie_file, JSON.dump(cookies))
    end

    def load_cookies
      return unless File.exist?(cookie_file)

      cookies = JSON.parse(File.read(cookie_file))
      cookies.each do |cookie|
        @browser.cookies.set(
          name: cookie["name"],
          value: cookie["value"],
          domain: cookie["domain"],
          path: cookie["path"] || "/",
          expires: cookie["expires"],
          secure: cookie["secure"],
          httponly: cookie["httpOnly"]
        )
      rescue StandardError
        # Ignore invalid cookies
      end
    end

    def cookie_file
      File.join(session_dir, "cookies.json")
    end

    def current_page
      PageWrapper.new(@browser)
    end

    private

    def ensure_logged_in_for_course(_course_id)
      ensure_logged_in
    end

    def ensure_logged_in(_course_id = nil, _chapter_id = nil)
      return if logged_in?

      if session_valid?
        @logged_in = true
        return
      end

      login("#{BASE_URL}/auth/zen_id")
    end

    def session_valid?
      start_browser
      load_cookies
      @browser.go_to(BASE_URL)
      wait_for_page_load

      # Try to fetch user info - if it succeeds, session is valid
      result = @browser.evaluate_async(%(
        fetch("#{API_URL}/v1/users?revision=2", {
          credentials: "include"
        })
        .then(response => response.json())
        .then(data => arguments[0](data))
        .catch(err => arguments[0]({error: err.message}));
      ), 10)

      # If we get user data (not an error), session is valid
      result.is_a?(Hash) && (result["id"] || result["zane_user_id"]) && !result["error"]
    rescue StandardError
      false
    end

    def fetch_api(path)
      start_browser

      result = @browser.evaluate_async(%(
        fetch("#{API_URL}#{path}", {
          credentials: "include"
        })
        .then(response => response.json())
        .then(data => arguments[0](data))
        .catch(err => arguments[0]({error: err.message}));
      ), 15)

      raise Error, "API error: #{result['error']}" if result.is_a?(Hash) && result["error"]

      result
    end

    def start_browser
      return if @browser

      @browser = Ferrum::Browser.new(
        headless: true,
        timeout: 30,
        window_size: [1920, 1080],
        browser_options: {
          "user-data-dir" => session_dir
        }
      )
    end

    def session_dir
      dir = File.expand_path("~/.zen-downloader/session")
      FileUtils.mkdir_p(dir)
      dir
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

  class Course
    attr_reader :id, :title, :chapters

    def initialize(data)
      course = data["course"]
      @id = course["id"]
      @title = course.dig("subject_category", "title") || course["title"]
      @chapters = course["chapters"].map { |c| ChapterInfo.new(c) }
    end
  end

  class ChapterInfo
    attr_reader :id, :title

    def initialize(data)
      @id = data["id"]
      @title = data["title"]
    end
  end

  class Chapter
    attr_reader :id, :title, :course_id, :course_title, :sections

    def initialize(data, course_id, course_title = nil)
      @course_id = course_id
      @course_title = course_title
      @data = data
      chapter = data["chapter"]
      @id = chapter["id"]
      @title = chapter["title"]
      @sections = chapter["sections"].map { |s| Section.new(s) }
    end

    def movies
      @sections.select(&:movie?)
    end
  end

  class Section
    attr_reader :id, :title, :resource_type, :length, :content_url

    def initialize(data)
      @id = data["id"]
      @title = data["title"]
      @resource_type = data["resource_type"]
      @length = data["length"]
      @content_url = data["content_url"]
    end

    def movie?
      @resource_type == "movie"
    end

    def formatted_length
      return nil unless @length

      minutes = @length / 60
      seconds = @length % 60
      format("%d:%02d", minutes, seconds)
    end
  end

  class MovieInfo
    attr_reader :id, :title, :length, :hls_url

    def initialize(data)
      @id = data["id"]
      @title = data["title"]
      @length = data["length"]
      @hls_url = extract_hls_url(data)
    end

    def formatted_length
      return nil unless @length

      minutes = @length / 60
      seconds = @length % 60
      format("%d:%02d", minutes, seconds)
    end

    private

    def extract_hls_url(data)
      videos = data["videos"]
      return nil unless videos&.any?

      video = videos.first
      video.dig("files", "hls", "url")
    end
  end
end
