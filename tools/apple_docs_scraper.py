#!/usr/bin/env python3
"""
Apple Documentation Scraper using Playwright
Scrapes Apple Developer documentation pages that require JavaScript
"""

from playwright.sync_api import sync_playwright
from bs4 import BeautifulSoup
import time
import json
import sys
from urllib.parse import urljoin, urlparse

class AppleDocsScraper:
    def __init__(self, target_url=None):
        self.base_url = "https://developer.apple.com"
        self.target_url = target_url or "https://developer.apple.com/documentation/foundationmodels"
        self.scraped_data = []
        
    def scrape_page(self, url, browser):
        """Scrape a single page using Playwright"""
        try:
            print(f"Scraping: {url}")
            
            page = browser.new_page()
            page.goto(url, wait_until="networkidle")
            
            # Wait for content to load
            page.wait_for_timeout(2000)
            
            # Get the rendered HTML
            content = page.content()
            page.close()
            
            soup = BeautifulSoup(content, 'html.parser')
            
            # Extract page data
            page_data = {
                'url': url,
                'title': self.extract_title(soup),
                'content': self.extract_content(soup),
                'links': self.extract_links(soup, url)
            }
            
            return page_data
            
        except Exception as e:
            print(f"Error scraping {url}: {e}")
            return None
    
    def extract_title(self, soup):
        """Extract page title"""
        title_selectors = [
            'h1',
            '.page-title',
            'title',
            '.hero-headline'
        ]
        
        for selector in title_selectors:
            title_elem = soup.select_one(selector)
            if title_elem:
                return title_elem.get_text().strip()
        
        return "No title found"
    
    def extract_content(self, soup):
        """Extract main content from the page"""
        content_selectors = [
            '.content',
            '.documentation-content',
            'main',
            '.article-content',
            '.page-content'
        ]
        
        content_parts = []
        
        # Try different content selectors
        for selector in content_selectors:
            content_elem = soup.select_one(selector)
            if content_elem:
                content_parts.append(content_elem.get_text().strip())
                break
        
        # If no main content found, get all paragraphs and headers
        if not content_parts:
            for elem in soup.find_all(['p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li']):
                text = elem.get_text().strip()
                if text:
                    content_parts.append(text)
        
        return '\n'.join(content_parts)
    
    def extract_links(self, soup, base_url):
        """Extract relevant documentation links"""
        links = []
        
        for link in soup.find_all('a', href=True):
            href = link['href']
            
            # Convert relative URLs to absolute
            if href.startswith('/'):
                href = urljoin(self.base_url, href)
            elif href.startswith('./') or href.startswith('../'):
                href = urljoin(base_url, href)
            
            # Only include Apple documentation links
            if 'developer.apple.com/documentation' in href:
                link_text = link.get_text().strip()
                if link_text:
                    links.append({
                        'url': href,
                        'text': link_text
                    })
        
        return links
    
    def save_data(self, filename='apple_foundation_models_docs.json'):
        """Save scraped data to JSON file"""
        with open(filename, 'w', encoding='utf-8') as f:
            json.dump(self.scraped_data, f, indent=2, ensure_ascii=False)
        print(f"Data saved to {filename}")
    
    def save_markdown(self, filename='apple_foundation_models_docs.md'):
        """Save scraped data to Markdown file"""
        with open(filename, 'w', encoding='utf-8') as f:
            f.write("# Apple Foundation Models Documentation\n\n")
            
            for page in self.scraped_data:
                f.write(f"## {page['title']}\n\n")
                f.write(f"**URL:** {page['url']}\n\n")
                f.write(f"{page['content']}\n\n")
                
                if page['links']:
                    f.write("### Related Links\n\n")
                    for link in page['links']:
                        f.write(f"- [{link['text']}]({link['url']})\n")
                    f.write("\n")
                
                f.write("---\n\n")
        
        print(f"Markdown saved to {filename}")
    
    def run(self, max_pages=10):
        """Run the scraper"""
        print("Starting Apple documentation scraper...")
        
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            
            visited_urls = set()
            urls_to_visit = [self.target_url]
            
            page_count = 0
            
            while urls_to_visit and page_count < max_pages:
                url = urls_to_visit.pop(0)
                
                if url in visited_urls:
                    continue
                    
                visited_urls.add(url)
                
                page_data = self.scrape_page(url, browser)
                if page_data:
                    self.scraped_data.append(page_data)
                    
                    # Add new documentation links to visit
                    for link in page_data['links']:
                        link_url = link['url']
                        # Only crawl related pages
                        if link_url not in visited_urls:
                            urls_to_visit.append(link_url)
                    
                    page_count += 1
                    time.sleep(1)  # Be respectful to the server
            
            browser.close()
        
        print(f"Scraped {len(self.scraped_data)} pages")
        
        # Save data
        self.save_data()
        self.save_markdown()
        
        return self.scraped_data

def main():
    # Check if URL is provided as argument
    target_url = sys.argv[1] if len(sys.argv) > 1 else None
    
    scraper = AppleDocsScraper(target_url)
    
    print("Apple Documentation Scraper (Playwright)")
    print("=" * 50)
    print(f"Target URL: {scraper.target_url}")
    print()
    
    try:
        data = scraper.run(max_pages=1)  # Only scrape single page by default
        print(f"\nScraping completed! Found {len(data)} pages.")
        print("Files created:")
        print("- apple_foundation_models_docs.json")
        print("- apple_foundation_models_docs.md")
        
    except KeyboardInterrupt:
        print("\nScraping interrupted by user")
    except Exception as e:
        print(f"Error during scraping: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()