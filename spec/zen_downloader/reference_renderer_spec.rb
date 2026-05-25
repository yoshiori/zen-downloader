# frozen_string_literal: true

require "spec_helper"

RSpec.describe ZenDownloader::ReferenceRenderer do
  describe ".detect_type" do
    it "detects slides when the kagai slide viewer asset is present" do
      type = described_class.detect_type(
        asset_urls: ["https://cdn.nnn.ed.nico/drive/kagai/assets/script.js"],
        images: [{ "w" => 1920, "h" => 1080 }, { "w" => 1920, "h" => 1080 }],
        text_length: 50
      )
      expect(type).to eq(:slides)
    end

    it "detects html when the quarto document asset is present" do
      type = described_class.detect_type(
        asset_urls: ["https://cdn.nnn.ed.nico/drive/zen_university/assets/zen_math/02A003/quarto-html/quarto.js"],
        images: [{ "w" => 1326, "h" => 852 }],
        text_length: 11_726
      )
      expect(type).to eq(:html)
    end

    it "falls back to html when the page has substantial text" do
      type = described_class.detect_type(asset_urls: [], images: [{ "w" => 1200, "h" => 800 }], text_length: 5000)
      expect(type).to eq(:html)
    end

    it "falls back to slides when there are multiple images and little text" do
      type = described_class.detect_type(
        asset_urls: [],
        images: [{ "w" => 1920, "h" => 1080 }, { "w" => 1920, "h" => 1080 }],
        text_length: 100
      )
      expect(type).to eq(:slides)
    end

    it "defaults to html when there is no clear signal" do
      type = described_class.detect_type(asset_urls: [], images: [], text_length: 0)
      expect(type).to eq(:html)
    end
  end

  describe ".content_signature" do
    it "is stable across requests where only the signed URL prefix differs" do
      images_a = [{ "src" => "https://cdn-private.nnn.ed.nico/cff/AAA/h1/54f0e44e-private.png?Policy=x" }]
      images_b = [{ "src" => "https://cdn-private.nnn.ed.nico/cff/BBB/h2/54f0e44e-private.png?Policy=y" }]

      sig_a = described_class.content_signature(images: images_a, text_length: 11_726)
      sig_b = described_class.content_signature(images: images_b, text_length: 11_726)
      expect(sig_a).to eq(sig_b)
    end

    it "differs when the underlying images differ" do
      images_a = [{ "src" => "https://cdn-private.nnn.ed.nico/cff/AAA/h1/aaaaaaaa-private.png" }]
      images_b = [{ "src" => "https://cdn-private.nnn.ed.nico/cff/AAA/h1/bbbbbbbb-private.png" }]

      expect(described_class.content_signature(images: images_a, text_length: 100))
        .not_to eq(described_class.content_signature(images: images_b, text_length: 100))
    end

    it "differs for image-less documents with different text length" do
      expect(described_class.content_signature(images: [], text_length: 100))
        .not_to eq(described_class.content_signature(images: [], text_length: 200))
    end

    it "is order-independent for the image set" do
      a = [{ "src" => "https://x/1-private.png" }, { "src" => "https://x/2-private.png" }]
      b = [{ "src" => "https://x/2-private.png" }, { "src" => "https://x/1-private.png" }]
      expect(described_class.content_signature(images: a, text_length: 0))
        .to eq(described_class.content_signature(images: b, text_length: 0))
    end
  end

  describe ".build_slide_html" do
    let(:images) do
      [
        { path: "/tmp/zen/001.png", w: 1920, h: 1080 },
        { path: "/tmp/zen/002.png", w: 1920, h: 1080 }
      ]
    end

    it "sets the CSS page size to the slide pixel dimensions" do
      html = described_class.build_slide_html(images)
      expect(html).to include("@page{size:1920px 1080px;margin:0}")
    end

    it "embeds every image via a file:// URL" do
      html = described_class.build_slide_html(images)
      expect(html).to include("file:///tmp/zen/001.png")
      expect(html).to include("file:///tmp/zen/002.png")
    end

    it "puts each slide on its own page" do
      html = described_class.build_slide_html(images)
      expect(html).to include("page-break-after:always")
    end
  end
end
