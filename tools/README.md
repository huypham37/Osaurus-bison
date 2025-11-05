# Web Scraping Tools

Tools for scraping JavaScript-heavy Apple developer documentation using Playwright.

## Setup

```bash
# Install Python dependencies
pip3 install -r requirements.txt

# Install Playwright browsers
playwright install chromium
```

## Scripts

### apple_docs_scraper.py
General-purpose scraper for Apple documentation pages requiring JavaScript.

```bash
# Scrape Foundation Models documentation (default)
./apple_docs_scraper.py

# Scrape a custom URL
./apple_docs_scraper.py "https://developer.apple.com/documentation/..."
```

Outputs: `apple_foundation_models_docs.json` and `apple_foundation_models_docs.md`

### scrape_liquid_glass.py
Specialized scraper for Apple Liquid Glass UI documentation.

```bash
./scrape_liquid_glass.py
```

Outputs: `liquid_glass_docs.json` and `liquid_glass_docs.txt`

## Notes

- Both scripts require Playwright with Chromium browser installed
- Scrapers are respectful with 1-3 second delays between requests
- Output files are saved to the repository root by default
