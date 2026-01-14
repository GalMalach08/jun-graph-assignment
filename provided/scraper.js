/**
 * Web Scraper Utility - PROVIDED
 * Fetches the raw HTML content from a URL.
 *
 * Usage (CLI):
 *   node scraper.js <url>
 *
 * Usage (Module):
 *   const { fetchHtml } = require('./provided/scraper.js');
 *   const html = await fetchHtml('https://example.com');
 */

const https = require("https");
const http = require("http");
const { URL } = require("url");

/**
 * Fetches a URL and returns its raw HTML content
 *
 * @param {string} url - The URL to fetch
 * @param {number} timeout - Request timeout in milliseconds
 * @returns {Promise<string>} - Raw HTML content
 */
function fetchHtml(url, timeout = 30000) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const protocol = parsedUrl.protocol === "https:" ? https : http;

    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port,
      path: parsedUrl.pathname + parsedUrl.search,
      method: "GET",
      headers: {
        "User-Agent": "Mozilla/5.0 (compatible; KnowledgeGraphBot/1.0)",
      },
      timeout: timeout,
    };

    const req = protocol.request(options, (res) => {
      // Handle redirects
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        fetchHtml(res.headers.location, timeout).then(resolve).catch(reject);
        return;
      }

      if (res.statusCode !== 200) {
        reject(new Error(`HTTP ${res.statusCode}: ${res.statusMessage}`));
        return;
      }

      let data = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve(data));
    });

    req.on("error", reject);
    req.on("timeout", () => {
      req.destroy();
      reject(new Error("Request timeout"));
    });

    req.end();
  });
}

// CLI usage
if (require.main === module) {
  const url = process.argv[2];

  if (!url) {
    console.log("Usage: node scraper.js <url>");
    console.log("Example: node scraper.js https://example.com");
    process.exit(1);
  }

  console.log(`Fetching: ${url}\n`);

  fetchHtml(url)
    .then((html) => console.log(html))
    .catch((error) => {
      console.error(`Error: ${error.message}`);
      process.exit(1);
    });
}

module.exports = { fetchHtml };
