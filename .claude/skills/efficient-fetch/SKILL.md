---
name: efficient-fetch
description: >
  Fetch and extract readable text content from public URLs using a fast,
  reliable method that avoids common failure modes (403 blocks, Chrome/browser
  dependencies, Wayback Machine errors). Use this skill whenever the user asks
  you to read, summarize, or extract information from a website, web page, URL,
  or online document — especially license pages, terms of service, documentation,
  articles, or any publicly accessible page. Trigger this skill proactively
  whenever you need to retrieve content from a URL rather than defaulting to
  WebFetch or browser automation.
---

# Efficient Web Content Fetcher

## Strategy: Jina Reader First

The fastest and most reliable method for fetching public web pages is the
**Jina Reader proxy**. Prepend `https://r.jina.ai/` to any target URL and pass
it to `WebFetch`. Jina renders the page server-side and returns clean markdown
text, bypassing most 403 blocks and JavaScript rendering requirements.

```
WebFetch: https://r.jina.ai/<target-url>
```

**Example:**
- Target: `https://pixabay.com/service/license-summary/`
- Fetch URL: `https://r.jina.ai/https://pixabay.com/service/license-summary/`

## Ordered Approach

Work through these steps in order. Stop as soon as one succeeds.

### Step 1 — Jina Reader (do this first, always)
```
WebFetch("https://r.jina.ai/<url>")
```
This works for the majority of public pages including documentation, license
pages, articles, and help centers. Try this before anything else.

### Step 2 — Jina Reader on a sub-page (if Step 1 is blocked)
Some sites block their main domain but allow specific help articles or
subpages. Try:
- The site's help center URL (e.g. `help.example.com/articles/...`)
- A more specific page path that contains the same information

### Step 3 — Transparent knowledge fallback
If all fetch methods fail (403, 451, CAPTCHA, connection refused), do NOT
silently make up content. Instead:
- State clearly that the live page could not be retrieved and why
- Provide what you know from training data if the topic is well-established
  (e.g. major platform license policies, widely-documented APIs)
- Explicitly label it as training knowledge with the caveat it may be outdated
- Give the user the direct URL to verify themselves

## What NOT to Try

These approaches were tested and consistently fail or are too slow — skip them:

| Method | Why it fails |
|--------|-------------|
| Direct `WebFetch(<url>)` | Returns 403 on most popular sites |
| `agent-browser open <url>` | Requires Chrome; fails silently in WSL2/headless environments without system libs |
| Wayback Machine (`web.archive.org/web/...`) | Returns 451 errors for many sites |
| Google cache (`webcache.googleusercontent.com/...`) | Returns 429 CAPTCHA |
| Python `scrapling` / `requests` | Dependencies rarely pre-installed; adds setup time |

## Output Format

When returning fetched content:

1. **State the exact URL you successfully fetched from** (evidence)
2. **State the method used** (Jina Reader / training knowledge)
3. **Present the content clearly** — use tables, bullet points, or headers as
   appropriate for the content type
4. **Flag uncertainty** if using training knowledge instead of a live fetch

## Example Output Pattern

```
**Source:** https://r.jina.ai/https://example.com/license (live fetch ✅)

### What's Allowed
- ...

### What's NOT Allowed
- ...

### Attribution
- ...
```

Or for training knowledge fallback:

```
**Source:** Training knowledge — live page blocked (403) at https://example.com/license
⚠️ This reflects policy as of my knowledge cutoff. Verify at the URL above.

### What's Allowed
- ...
```
