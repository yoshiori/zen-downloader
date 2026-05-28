# frozen_string_literal: true

require "spec_helper"

RSpec.describe ZenDownloader::Reference do
  it "exposes a title and url" do
    ref = described_class.new(title: "教材A", url: "https://example.com/a")
    expect(ref.title).to eq("教材A")
    expect(ref.url).to eq("https://example.com/a")
  end
end

RSpec.describe ZenDownloader::MovieInfo do
  describe "#references" do
    it "extracts references from the movie reference schema (content_urls array)" do
      data = {
        "id" => 31_478_168_554,
        "title" => "講師紹介/コースの概要",
        "references" => [
          {
            "reference_type" => "html",
            "content_urls" => ["https://www.nnn.ed.nico/contents/courses/1/chapters/2/movies/3/references"]
          }
        ]
      }
      movie = described_class.new(data)
      expect(movie.references.length).to eq(1)
      expect(movie.references.first.url)
        .to eq("https://www.nnn.ed.nico/contents/courses/1/chapters/2/movies/3/references")
      expect(movie.references.first.title).to eq("講師紹介/コースの概要")
    end

    it "returns an empty array when there are no references" do
      movie = described_class.new("id" => 1, "title" => "t")
      expect(movie.references).to eq([])
    end

    it "flattens multiple content_urls into separate references" do
      data = {
        "title" => "t",
        "references" => [{ "reference_type" => "html", "content_urls" => %w[https://a https://b] }]
      }
      movie = described_class.new(data)
      expect(movie.references.map(&:url)).to eq(%w[https://a https://b])
    end
  end
end

RSpec.describe ZenDownloader::Lesson do
  let(:data) do
    {
      "lesson" => {
        "id" => 55_410_154_544,
        "title" => "数字で見るIT革命（後半）",
        "references" => [
          {
            "id" => nil,
            "title" => "ネットワーク産業論_04",
            "content_url" => "https://www.nnn.ed.nico/contents/courses/1/chapters/2/lessons/3/references?content_type=zen_univ"
          }
        ]
      }
    }
  end

  describe "#initialize" do
    it "extracts id and title" do
      lesson = described_class.new(data)
      expect(lesson.id).to eq(55_410_154_544)
      expect(lesson.title).to eq("数字で見るIT革命（後半）")
    end
  end

  describe "#references" do
    it "extracts references from the lesson reference schema (content_url)" do
      lesson = described_class.new(data)
      expect(lesson.references.length).to eq(1)
      expect(lesson.references.first.title).to eq("ネットワーク産業論_04")
      expect(lesson.references.first.url).to include("/lessons/3/references")
    end

    it "returns an empty array when references key is missing" do
      lesson = described_class.new("lesson" => { "id" => 1, "title" => "t" })
      expect(lesson.references).to eq([])
    end
  end
end

RSpec.describe ZenDownloader::Chapter do
  let(:data) do
    {
      "chapter" => {
        "id" => "ch1",
        "title" => "第1章",
        "sections" => [
          { "id" => 1, "resource_type" => "movie", "title" => "動画" },
          { "id" => 2, "resource_type" => "exercise", "title" => "確認テスト" },
          { "id" => 3, "resource_type" => "lesson", "title" => "授業" },
          { "id" => 4, "resource_type" => "report", "title" => "レポート" }
        ]
      }
    }
  end

  describe "#reference_sections" do
    it "returns only movie and lesson sections (which can carry references)" do
      chapter = described_class.new(data, "course1", "コース")
      types = chapter.reference_sections.map(&:resource_type)
      expect(types).to eq(%w[movie lesson])
    end
  end

  describe "#exercise_sections" do
    it "returns only exercise and report sections (which carry confirmation questions)" do
      chapter = described_class.new(data, "course1", "コース")
      types = chapter.exercise_sections.map(&:resource_type)
      expect(types).to eq(%w[exercise report])
    end
  end
end
