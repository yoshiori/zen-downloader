# frozen_string_literal: true

require "ferrum"
require "fileutils"
require "json"
require "net/http"
require "tmpdir"

module ZenDownloader
  class Client
    BASE_URL = "https://www.nnn.ed.nico"
    API_URL = "https://api.nnn.ed.nico"
    # Safety cap so a page that never stops growing can't loop forever.
    MAX_LAZY_SCROLLS = 50

    def initialize(config)
      @config = config
      @browser = nil
      @logged_in = false
    end

    def login
      start_browser

      # Step 1: Access ZEN ID login page directly
      @browser.go_to("#{BASE_URL}/auth/zen_id")
      wait_for_page_load

      # Step 2: Submit email (first step of Auth0 Universal Login)
      email_field = wait_for_element('input[type="email"], input[name="username"]')
      raise Error, "Email field not found" unless email_field

      email_field.focus.type(@config.username)
      submit_button = @browser.at_css('button[type="submit"]')
      submit_button.click
      wait_for_page_load

      # Step 3: Submit password (second step)
      password_field = wait_for_element('input[type="password"], input[name="password"]')
      raise Error, "Password field not found" unless password_field

      password_field.focus.type(@config.password)
      submit_button = @browser.at_css('button[type="submit"]')
      submit_button.click
      wait_for_page_load

      # Check for authentication error
      check_authentication_error

      # Step 4: Login successful
      @logged_in = true
      current_page
    end

    def fetch_page(url)
      ensure_logged_in
      get_page(url)
    end

    def fetch_course(course_id)
      ensure_logged_in

      data = fetch_api("/v2/material/courses/#{course_id}?revision=1")
      Course.new(data)
    end

    def fetch_chapter(course_id, chapter_id)
      ensure_logged_in

      # Fetch course info to get course title
      course_data = fetch_api("/v2/material/courses/#{course_id}?revision=1")
      course = course_data["course"]

      # Use subject_category title (e.g., "法学Ⅰ") as the main course name
      course_title = course.dig("subject_category", "title") || course["title"]

      data = fetch_api("/v2/material/courses/#{course_id}/chapters/#{chapter_id}?revision=1")
      Chapter.new(data, course_id, course_title)
    end

    def fetch_movie_info(course_id, chapter_id, movie_id)
      ensure_logged_in

      data = fetch_api("/v2/material/courses/#{course_id}/chapters/#{chapter_id}/movies/#{movie_id}?revision=1")
      MovieInfo.new(data)
    end

    def fetch_lesson(course_id, chapter_id, lesson_id)
      ensure_logged_in

      data = fetch_api("/v1/n_school/courses/#{course_id}/chapters/#{chapter_id}/lessons/#{lesson_id}?revision=1")
      Lesson.new(data)
    end

    # Reference material lives in different places depending on section type.
    def fetch_section_references(course_id, chapter_id, section)
      case section.resource_type
      when "movie"
        fetch_movie_info(course_id, chapter_id, section.id).references
      when "lesson"
        fetch_lesson(course_id, chapter_id, section.id).references
      else
        []
      end
    end

    # Render a reference page to a PDF, picking the strategy that fits the
    # page (slide deck vs HTML document).
    #
    # Returns [result, signature] where result is :slides, :html, or :duplicate.
    # When the page's content signature is in skip_signatures, rendering is
    # skipped (the same document is often linked from every section of a
    # chapter); the caller can collect signatures to dedupe across sections.
    def render_reference_to_pdf(reference, output_path, skip_signatures: [])
      ensure_logged_in
      start_browser

      @browser.go_to(reference.url)
      wait_for_page_load
      scroll_to_load_lazy_content

      info = collect_reference_page_info
      signature = ReferenceRenderer.content_signature(
        images: info["images"],
        text_length: info["textLength"]
      )
      return [:duplicate, signature] if skip_signatures.include?(signature)

      type = ReferenceRenderer.detect_type(
        asset_urls: info["assets"],
        images: info["images"],
        text_length: info["textLength"]
      )

      if type == :slides && !info["images"].empty?
        build_pdf_from_slides(info["images"], output_path)
      else
        print_page_to_pdf(output_path)
        type = :html
      end

      [type, signature]
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

    def ensure_logged_in
      return if logged_in?

      if session_valid?
        @logged_in = true
        return
      end

      login
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

    # Reference pages lazy-load their images; scroll until the page stops
    # growing so every image is triggered regardless of document length.
    def scroll_to_load_lazy_content
      MAX_LAZY_SCROLLS.times do
        last_y = @browser.evaluate("window.scrollY")
        @browser.execute("window.scrollBy(0, window.innerHeight)")
        sleep 0.3
        break if @browser.evaluate("window.scrollY") == last_y
      end
      @browser.execute("window.scrollTo(0, 0)")
      sleep 0.5
    rescue StandardError
      nil
    end

    # Snapshot the rendered reference page: its asset URLs, the private slide
    # images (with natural dimensions), and how much body text it carries.
    def collect_reference_page_info
      @browser.evaluate(<<~JS)
        (() => ({
          assets: Array.from(document.querySelectorAll('script[src],link[href]'))
                       .map(e => e.src || e.href),
          images: Array.from(document.querySelectorAll('img'))
                       .map(i => ({ src: i.currentSrc || i.src, w: i.naturalWidth, h: i.naturalHeight }))
                       .filter(o => /cdn-private\\.nnn\\.ed\\.nico/.test(o.src)),
          textLength: document.body.innerText.length
        }))()
      JS
    end

    # Download each slide image and lay them out one-per-page for print-to-PDF.
    def build_pdf_from_slides(images_info, output_path)
      Dir.mktmpdir("zen_slides") do |tmp|
        images = images_info.each_with_index.map do |img, i|
          path = File.join(tmp, format("%03d.png", i + 1))
          File.binwrite(path, Net::HTTP.get(URI(img["src"])))
          { path: path, w: img["w"], h: img["h"] }
        end

        html_path = File.join(tmp, "slides.html")
        File.write(html_path, ReferenceRenderer.build_slide_html(images))
        @browser.go_to("file://#{html_path}")
        sleep 0.5

        w = images.first[:w]
        h = images.first[:h]
        @browser.pdf(
          path: output_path,
          paper_width: w / 96.0,
          paper_height: h / 96.0,
          margin_top: 0, margin_bottom: 0, margin_left: 0, margin_right: 0,
          print_background: true,
          prefer_css_page_size: true
        )
      end
    end

    # Capture the current page as an A4 PDF (for HTML document references).
    def print_page_to_pdf(output_path)
      @browser.pdf(
        path: output_path,
        paper_width: 8.27,
        paper_height: 11.69,
        margin_top: 0.4, margin_bottom: 0.4, margin_left: 0.4, margin_right: 0.4,
        print_background: true
      )
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

    # Sections whose detail can carry downloadable reference material.
    def reference_sections
      @sections.select { |s| %w[movie lesson].include?(s.resource_type) }
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

  # A single downloadable reference material (slide deck or HTML document).
  class Reference
    attr_reader :title, :url

    def initialize(title:, url:)
      @title = title
      @url = url
    end
  end

  # A "lesson" section (archived live class). Fetched from the n_school API,
  # which nests everything under a "lesson" key and exposes references as
  # { "title", "content_url" } entries.
  class Lesson
    attr_reader :id, :title, :references

    def initialize(data)
      lesson = data["lesson"]
      @id = lesson["id"]
      @title = lesson["title"]
      @references = (lesson["references"] || []).map do |ref|
        Reference.new(title: ref["title"] || @title, url: ref["content_url"])
      end
    end
  end

  class MovieInfo
    attr_reader :id, :title, :length, :hls_url, :references

    def initialize(data)
      @id = data["id"]
      @title = data["title"]
      @length = data["length"]
      @hls_url = extract_hls_url(data)
      @references = extract_references(data)
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

    # The movie reference schema groups one or more URLs under "content_urls".
    def extract_references(data)
      (data["references"] || []).flat_map do |ref|
        urls = ref["content_urls"] || Array(ref["content_url"])
        urls.compact.map { |url| Reference.new(title: @title, url: url) }
      end
    end
  end
end
