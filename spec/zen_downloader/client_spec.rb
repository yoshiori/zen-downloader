# frozen_string_literal: true

require "spec_helper"

RSpec.describe ZenDownloader::Client do
  let(:config) do
    instance_double(ZenDownloader::Config,
      username: "test@example.com",
      password: "test_password")
  end
  let(:client) { described_class.new(config) }
  let(:mock_browser) { instance_double(Ferrum::Browser) }
  let(:mock_network) { instance_double(Ferrum::Network) }

  before do
    allow(Ferrum::Browser).to receive(:new).and_return(mock_browser)
    allow(mock_browser).to receive(:network).and_return(mock_network)
    allow(mock_network).to receive(:wait_for_idle)
    allow(mock_browser).to receive(:quit)
  end

  describe "#login" do
    let(:target_url) { "https://www.nnn.ed.nico/courses/1234/chapters/5678" }
    let(:zen_link) { instance_double(Ferrum::Node) }
    let(:email_field) { instance_double(Ferrum::Node) }
    let(:password_field) { instance_double(Ferrum::Node) }
    let(:submit_button) { instance_double(Ferrum::Node) }

    context "when login succeeds" do
      before do
        allow(mock_browser).to receive(:go_to)
        allow(mock_browser).to receive(:at_css).with('a[href*="target_type=zen_id"]').and_return(zen_link)
        allow(zen_link).to receive(:click)

        allow(mock_browser).to receive(:at_css).with('input[type="email"], input[name="username"]').and_return(email_field)
        allow(email_field).to receive(:focus).and_return(email_field)
        allow(email_field).to receive(:type)

        allow(mock_browser).to receive(:at_css).with('button[type="submit"]').and_return(submit_button)
        allow(submit_button).to receive(:click)

        allow(mock_browser).to receive(:at_css).with('input[type="password"], input[name="password"]').and_return(password_field)
        allow(password_field).to receive(:focus).and_return(password_field)
        allow(password_field).to receive(:type)

        allow(mock_browser).to receive(:at_css).with("#error-element-password, .ulp-input-error-message, .error-message").and_return(nil)

        title_element = instance_double(Ferrum::Node, text: "Course Page")
        allow(mock_browser).to receive(:at_css).with("title").and_return(title_element)
        allow(mock_browser).to receive(:body).and_return("<html><body>Content</body></html>")
        allow(mock_browser).to receive(:current_url).and_return(target_url)
      end

      it "completes the login flow and returns the target page" do
        page = client.login(target_url)

        expect(page.title).to eq("Course Page")
        expect(client).to be_logged_in
      end

      it "enters email and password" do
        expect(email_field).to receive(:type).with("test@example.com")
        expect(password_field).to receive(:type).with("test_password")

        client.login(target_url)
      end
    end

    context "when login fails due to invalid credentials" do
      let(:error_element) { instance_double(Ferrum::Node, text: "Wrong email or password") }

      before do
        allow(mock_browser).to receive(:go_to)
        allow(mock_browser).to receive(:at_css).with('a[href*="target_type=zen_id"]').and_return(zen_link)
        allow(zen_link).to receive(:click)

        allow(mock_browser).to receive(:at_css).with('input[type="email"], input[name="username"]').and_return(email_field)
        allow(email_field).to receive(:focus).and_return(email_field)
        allow(email_field).to receive(:type)

        allow(mock_browser).to receive(:at_css).with('button[type="submit"]').and_return(submit_button)
        allow(submit_button).to receive(:click)

        allow(mock_browser).to receive(:at_css).with('input[type="password"], input[name="password"]').and_return(password_field)
        allow(password_field).to receive(:focus).and_return(password_field)
        allow(password_field).to receive(:type)

        allow(mock_browser).to receive(:at_css).with("#error-element-password, .ulp-input-error-message, .error-message").and_return(error_element)
      end

      it "raises an authentication error" do
        expect { client.login(target_url) }
          .to raise_error(ZenDownloader::AuthenticationError, /Wrong email or password/)
      end
    end

    context "when ZEN ID login link is not found" do
      before do
        allow(mock_browser).to receive(:go_to)
        allow(mock_browser).to receive(:at_css).with('a[href*="target_type=zen_id"]').and_return(nil)
      end

      it "raises an error" do
        expect { client.login(target_url) }
          .to raise_error(ZenDownloader::Error, /ZEN ID login link not found/)
      end
    end
  end

  describe "#fetch_page" do
    let(:target_url) { "https://www.nnn.ed.nico/courses/1234/chapters/5678" }

    context "when already logged in" do
      before do
        allow(client).to receive(:logged_in?).and_return(true)
        allow(mock_browser).to receive(:go_to)

        title_element = instance_double(Ferrum::Node, text: "Course Page")
        allow(mock_browser).to receive(:at_css).with("title").and_return(title_element)
        allow(mock_browser).to receive(:body).and_return("<html><body>Content</body></html>")
        allow(mock_browser).to receive(:current_url).and_return(target_url)
      end

      it "fetches the page without logging in again" do
        expect(client).not_to receive(:login)
        page = client.fetch_page(target_url)
        expect(page.title).to eq("Course Page")
      end
    end

    context "when not logged in" do
      it "logs in first then returns the page" do
        page_wrapper = instance_double(ZenDownloader::PageWrapper, title: "Course Page")
        expect(client).to receive(:login).with(target_url).and_return(page_wrapper)

        page = client.fetch_page(target_url)
        expect(page.title).to eq("Course Page")
      end
    end
  end

  describe "#quit" do
    it "quits the browser" do
      client.send(:start_browser)
      expect(mock_browser).to receive(:quit)
      client.quit
    end
  end
end

RSpec.describe ZenDownloader::PageWrapper do
  let(:mock_browser) { instance_double(Ferrum::Browser) }
  let(:page_wrapper) { described_class.new(mock_browser) }

  describe "#title" do
    it "returns the page title" do
      title_element = instance_double(Ferrum::Node, text: "Test Title")
      allow(mock_browser).to receive(:at_css).with("title").and_return(title_element)

      expect(page_wrapper.title).to eq("Test Title")
    end

    it "returns nil when title element is not found" do
      allow(mock_browser).to receive(:at_css).with("title").and_return(nil)

      expect(page_wrapper.title).to be_nil
    end
  end

  describe "#body" do
    it "returns the page body" do
      allow(mock_browser).to receive(:body).and_return("<html><body>Content</body></html>")

      expect(page_wrapper.body).to eq("<html><body>Content</body></html>")
    end
  end

  describe "#url" do
    it "returns the current URL" do
      allow(mock_browser).to receive(:current_url).and_return("https://example.com")

      expect(page_wrapper.url).to eq("https://example.com")
    end
  end
end
