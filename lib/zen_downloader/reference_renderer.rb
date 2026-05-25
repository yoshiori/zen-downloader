# frozen_string_literal: true

require "digest"
require "uri"

module ZenDownloader
  # Pure helpers for turning a lesson/movie reference page into a PDF.
  #
  # Reference material on ZEN Study comes in two shapes that need different
  # handling:
  #   - :slides — a slide viewer (the "kagai" player) showing full-page images,
  #               best rebuilt as one image per PDF page.
  #   - :html   — a rich HTML document (e.g. a Quarto article) with inline
  #               figures, best captured via the browser's print-to-PDF.
  module ReferenceRenderer
    SLIDE_ASSET_MARKER = "drive/kagai"
    HTML_ASSET_MARKER = "quarto-html"
    # A document this wordy is prose, not slides, regardless of its images.
    TEXT_LENGTH_THRESHOLD = 2000

    # Decide how to render a reference page from a snapshot of its DOM.
    # asset_urls: <script>/<link> URLs, images: [{ "w" =>, "h" => }, ...].
    def self.detect_type(asset_urls:, images:, text_length:)
      return :slides if asset_urls.any? { |u| u.to_s.include?(SLIDE_ASSET_MARKER) }
      return :html if asset_urls.any? { |u| u.to_s.include?(HTML_ASSET_MARKER) }
      return :html if text_length > TEXT_LENGTH_THRESHOLD
      return :slides if images.length >= 2

      :html
    end

    # A stable fingerprint of a reference's content, used to skip duplicates
    # within a chapter (the same document is often linked from every section).
    # Image file names are content-addressed, so they stay constant even though
    # the signed CDN URL prefix changes on every request.
    def self.content_signature(images:, text_length:)
      basenames = images.map { |img| image_basename(img["src"].to_s) }.sort
      Digest::MD5.hexdigest("#{text_length}|#{basenames.join(',')}")
    end

    # Extract the file name from an image URL, tolerating URLs that aren't
    # strictly valid (unescaped characters would otherwise raise).
    def self.image_basename(src)
      File.basename(URI(src).path)
    rescue URI::InvalidURIError
      File.basename(src.split(/[?#]/).first.to_s)
    end

    # Build a standalone HTML page that lays out each slide image on its own
    # page sized to the image, so print-to-PDF yields one slide per page.
    # images: [{ path:, w:, h: }, ...].
    def self.build_slide_html(images)
      return "" if images.empty?

      w = images.first[:w]
      h = images.first[:h]

      style = "@page{size:#{w}px #{h}px;margin:0}" \
              "html,body{margin:0;padding:0}" \
              "img{display:block;width:#{w}px;height:#{h}px;page-break-after:always}"
      body = images.map { |img| "<img src='file://#{img[:path]}'>" }.join

      "<!doctype html><html><head><meta charset='utf-8'><style>#{style}</style></head><body>#{body}</body></html>"
    end
  end
end
