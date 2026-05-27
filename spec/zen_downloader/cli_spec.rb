# frozen_string_literal: true

require "spec_helper"

RSpec.describe ZenDownloader::CLI do
  let(:cli) { described_class.new }

  describe "#parse_url (private)" do
    it "parses chapter URL correctly" do
      result = cli.send(:parse_url, "https://www.nnn.ed.nico/courses/1234/chapters/5678")
      expect(result).to eq({ type: :chapter, course_id: "1234", chapter_id: "5678" })
    end

    it "parses course URL correctly" do
      result = cli.send(:parse_url, "https://www.nnn.ed.nico/courses/1234")
      expect(result).to eq({ type: :course, course_id: "1234" })
    end

    it "parses course URL with trailing slash" do
      result = cli.send(:parse_url, "https://www.nnn.ed.nico/courses/1234/")
      expect(result).to eq({ type: :course, course_id: "1234" })
    end

    it "raises error for invalid URL" do
      expect { cli.send(:parse_url, "https://example.com/invalid") }
        .to raise_error(ZenDownloader::Error, /Invalid URL/)
    end

    it "prefers chapter URL when both patterns could match" do
      result = cli.send(:parse_url, "https://www.nnn.ed.nico/courses/1234/chapters/5678")
      expect(result[:type]).to eq(:chapter)
    end
  end

  describe "download options" do
    let(:download_options) { described_class.commands["download"].options }

    it "downloads reference materials by default (opt-out via --no-references)" do
      expect(download_options[:references].default).to be(true)
    end

    it "does not restrict to references only by default" do
      expect(download_options[:references_only].default).to be(false)
    end

    it "saves confirmation exercises by default (opt-out via --no-exercises)" do
      expect(download_options[:exercises].default).to be(true)
    end
  end

  describe "#reference_filename (private)" do
    it "builds an indexed, sanitized PDF name" do
      name = cli.send(:reference_filename, 3, "数字で見る IT革命", 0, 1)
      expect(name).to eq("03_数字で見る_IT革命.pdf")
    end

    it "appends a suffix when a section has multiple references" do
      name = cli.send(:reference_filename, 1, "教材", 1, 2)
      expect(name).to eq("01_教材_2.pdf")
    end

    it "truncates an over-long multibyte title without exceeding the byte limit or breaking encoding" do
      name = cli.send(:reference_filename, 1, "あ" * 300, 0, 1)
      expect(name.bytesize).to be <= 255
      expect(name).to be_valid_encoding
      expect(name).to start_with("01_")
      expect(name).to end_with(".pdf")
    end
  end
end
