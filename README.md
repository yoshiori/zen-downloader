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
# Download all videos from a course
./dl https://www.nnn.ed.nico/courses/COURSE_ID

# Download all videos from a chapter
./dl https://www.nnn.ed.nico/courses/COURSE_ID/chapters/CHAPTER_ID

# With options
./dl -p 4 https://...  # 4 parallel downloads (default: 6)
./dl -o /path/to/dir https://...  # Custom output directory
```

## Other Commands

```bash
bin/zen-downloader list URL    # List chapters in a course or videos in a chapter
bin/zen-downloader login       # Test login
bin/zen-downloader version     # Show version
```

## License

GPL-3.0
