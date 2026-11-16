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

  # Later sections of a chapter stay locked until the earlier ones are done;
  # one locked section must not abort the whole download.
  describe "locked sections" do
    let(:client) { instance_double(ZenDownloader::Client) }
    let(:chapter) do
      ZenDownloader::Chapter.new(
        { "chapter" => { "id" => "ch", "title" => "Ch", "sections" => [
          { "id" => "m1", "title" => "Open", "resource_type" => "movie" },
          { "id" => "m2", "title" => "Locked", "resource_type" => "movie" }
        ] } },
        "c"
      )
    end
    let(:open_section) { chapter.sections[0] }
    let(:locked_section) { chapter.sections[1] }

    it "skips a locked video and keeps going" do
      allow(client).to receive(:fetch_movie_info).with("c", "ch", "m1")
        .and_return(instance_double(ZenDownloader::MovieInfo, hls_url: nil))
      allow(client).to receive(:fetch_movie_info).with("c", "ch", "m2")
        .and_raise(ZenDownloader::SectionLockedError, "locked")

      expect { cli.send(:download_videos, client, chapter, Dir.tmpdir, 1) }
        .to output(/Locked - Not unlocked yet, skipping/).to_stdout
    end

    it "skips a locked section when collecting reference materials" do
      allow(client).to receive(:fetch_section_references).with("c", "ch", open_section).and_return([])
      allow(client).to receive(:fetch_section_references).with("c", "ch", locked_section)
        .and_raise(ZenDownloader::SectionLockedError, "locked")

      expect { cli.send(:download_references, client, "c", "ch", chapter, Dir.tmpdir) }
        .to output(/Locked - Not unlocked yet, skipping/).to_stdout
    end

    # Writing an empty file would make later runs skip it as "already exists"
    # even after the exercise is unlocked and answered.
    it "does not save an exercise whose page has no content" do
      exercise_chapter = ZenDownloader::Chapter.new(
        { "chapter" => { "id" => "ch", "title" => "Ch", "sections" => [
          { "id" => "e1", "title" => "Quiz", "resource_type" => "exercise" }
        ] } },
        "c"
      )
      allow(client).to receive(:fetch_exercise)
        .and_return(instance_double(ZenDownloader::Exercise, empty?: true))

      Dir.mktmpdir do |dir|
        expect { cli.send(:download_exercises, client, exercise_chapter, dir) }
          .to output(/Quiz - No content yet/).to_stdout
        expect(Dir.children(dir)).to be_empty
      end
    end
  end
end
