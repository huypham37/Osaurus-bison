#!/usr/bin/env python3
"""
Scrape Apple Liquid Glass documentation using Playwright
"""

from playwright.sync_api import sync_playwright
import time
import json

def scrape_liquid_glass():
    url = "https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass"
    
    print(f"Scraping: {url}")
    
    with sync_playwright() as p:
        # Launch browser
        browser = p.chromium.launch(headless=True)
        page = browser.new_page()
        
        # Navigate to the page
        page.goto(url, wait_until="networkidle", timeout=30000)
        
        # Wait for content to load
        time.sleep(3)
        
        # Extract the main content
        content = page.evaluate("""() => {
            // Get the main content area
            const main = document.querySelector('main') || document.body;
            return main.innerText;
        }""")
        
        # Get the page title
        title = page.title()
        
        # Get all headings and paragraphs
        structured_content = page.evaluate("""() => {
            const elements = [];
            const selectors = ['h1', 'h2', 'h3', 'h4', 'p', 'li', 'code', 'pre'];
            
            selectors.forEach(selector => {
                document.querySelectorAll(selector).forEach(el => {
                    const text = el.innerText.trim();
                    if (text) {
                        elements.push({
                            tag: el.tagName.toLowerCase(),
                            text: text
                        });
                    }
                });
            });
            
            return elements;
        }""")
        
        browser.close()
        
        # Save the content
        result = {
            'url': url,
            'title': title,
            'content': content,
            'structured': structured_content
        }
        
        # Save to JSON
        with open('liquid_glass_docs.json', 'w', encoding='utf-8') as f:
            json.dump(result, f, indent=2, ensure_ascii=False)
        
        # Save to readable text file
        with open('liquid_glass_docs.txt', 'w', encoding='utf-8') as f:
            f.write(f"# {title}\n\n")
            f.write(f"URL: {url}\n\n")
            f.write("=" * 80 + "\n\n")
            f.write(content)
        
        print(f"\n✓ Successfully scraped!")
        print(f"  Title: {title}")
        print(f"  Content length: {len(content)} characters")
        print(f"  Structured elements: {len(structured_content)}")
        print(f"\nFiles created:")
        print(f"  - liquid_glass_docs.json")
        print(f"  - liquid_glass_docs.txt")
        
        return result

if __name__ == "__main__":
    try:
        scrape_liquid_glass()
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
