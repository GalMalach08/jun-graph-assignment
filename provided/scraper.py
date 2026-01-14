"""
Web Scraper Utility - PROVIDED
Fetches the raw HTML content from a URL.

Usage:
    python scraper.py <url>
    
    Or import in your code:
    from provided.scraper import fetch_html
    html = fetch_html("https://example.com")
"""

import re
import sys
from urllib.request import urlopen, Request
from typing import Optional


def fetch_html(
    url: str,
    timeout: int = 30,
    strip_js: bool = False,
    strip_style: bool = False
) -> str:
    """
    Fetches a URL and returns its raw HTML content.
    
    Args:
        url: The URL to fetch
        timeout: Request timeout in seconds
        strip_js: If True, removes all <script> tags and their content
        strip_style: If True, removes all <style> tags and their content
        
    Returns:
        Raw HTML content from the page
        
    Raises:
        Exception: If the URL cannot be fetched
    """
    headers = {
        'User-Agent': 'Mozilla/5.0 (compatible; KnowledgeGraphBot/1.0)'
    }

    request = Request(url, headers=headers)

    with urlopen(request, timeout=timeout) as response:
        html = response.read().decode('utf-8', errors='ignore')

    if strip_js:
        html = re.sub(r'<script\b[^>]*>[\s\S]*?</script>', '', html, flags=re.IGNORECASE)

    if strip_style:
        html = re.sub(r'<style\b[^>]*>[\s\S]*?</style>', '', html, flags=re.IGNORECASE)

    return html


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python scraper.py <url>")
        print("Example: python scraper.py https://example.com")
        sys.exit(1)

    url = sys.argv[1]
    print(f"Fetching: {url}\n")

    try:
        html = fetch_html(url)
        print(html)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
