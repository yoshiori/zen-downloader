# zen-downloader

A CLI tool to download course videos from ZEN University (nnn.ed.nico).

## Requirements

- Ruby 3.x
- Chrome/Chromium (for headless browser)
- ffmpeg

## Setup

```bash
bundle install
```

Create config file at `~/.zen-downloader.yml`:

```yaml
username: your_email@example.com
password: "your_password"
download_dir: ~/Videos/ZEN
```

## Usage

```bash
# Download videos and reference materials from a course
./dl https://www.nnn.ed.nico/courses/COURSE_ID

# Download videos and reference materials from a chapter
./dl https://www.nnn.ed.nico/courses/COURSE_ID/chapters/CHAPTER_ID

# With options
./dl -p 4 https://...  # 4 parallel downloads (default: 6)
./dl -o /path/to/dir https://...  # Custom output directory

# Reference materials (handouts/slides) as PDF
./dl --no-references https://...    # Videos only (skip reference PDFs)
./dl --references-only https://...  # Reference PDFs only (skip videos)
```

Reference materials (handouts/slides) are downloaded as PDF by default,
alongside the videos. Slide-deck references become one slide per page;
HTML document references are captured via the browser's print-to-PDF.
Within a chapter, materials shared by multiple sections are downloaded
only once.

## Other Commands

```bash
bin/zen-downloader list URL    # List chapters in a course or videos in a chapter
bin/zen-downloader login       # Test login
bin/zen-downloader version     # Show version
```

## License

GPL-3.0
