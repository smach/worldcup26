# worldcup26 live-score proxy (Cloudflare Worker)

A tiny serverless proxy that lets the static [worldcup26 Quarto
site](../index.qmd) refresh live scores from a button **without** rebuilding the
site and **without** exposing the football-data.org API key in the browser.

This is **optional**. If you don't deploy it (and don't set
`WORLDCUP26_SCORE_PROXY_URL` when rendering the site), the site works exactly as
before — there's simply no "Update scores" button. The R hourly/10-minute
rebuild pipeline is unaffected either way.

## What it does

- Holds your football-data.org key as a Cloudflare **secret** (never in code,
  never in the response).
- Fetches `competitions/WC/matches`, slims it to one small entry per match
  (`id`, `status`, `home`, `away`, `homePk`, `awayPk`, `utcDate`), and returns
  JSON with CORS headers so the page can `fetch()` it.
- **Edge-caches** for `CACHE_TTL_SECONDS` (default 30s), so many visitors
  clicking the button in the same window share a single upstream API call — this
  protects your rate limit on a public page.
- Only answers requests whose `Origin` is in `ALLOWED_ORIGINS`.

## Deploy

You need a (free) Cloudflare account and [Wrangler](https://developers.cloudflare.com/workers/wrangler/).

```bash
cd worker

# 1. Log in (opens a browser once).
npx wrangler login

# 2. Store the API key as a secret. Paste your PAID key for live scores
#    (the same one you'd put in FOOTBALL_DATA_API_KEY for live mode).
npx wrangler secret put FOOTBALL_DATA_API_KEY

# 3. (Optional) edit wrangler.toml: set ALLOWED_ORIGINS to your Pages origin.

# 4. Deploy.
npx wrangler deploy
```

`wrangler deploy` prints the public URL, e.g.
`https://worldcup26-scores.YOURNAME.workers.dev`.

## Turn the button on

Set that URL as `WORLDCUP26_SCORE_PROXY_URL` wherever the site is rendered:

- **Local preview:** add to `~/.Renviron`
  (`WORLDCUP26_SCORE_PROXY_URL=https://worldcup26-scores.YOURNAME.workers.dev`)
  and restart R.
- **GitHub Pages build:** add a repository **variable** (Settings → Secrets and
  variables → Actions → Variables) named `WORLDCUP26_SCORE_PROXY_URL`, then make
  `.github/workflows/publish.yml` pass it into the render env (see the note in
  that file). Leave it unset to keep the button off.

## Local development

```bash
cd worker
npx wrangler dev   # serves on http://localhost:8787
# In another shell:
curl -s -H "Origin: http://localhost:4321" http://localhost:8787 | head
```

Confirm the JSON shape, that no key appears anywhere in the output, and that a
request with a disallowed `Origin` is rejected with 403.

## Cost

The free Cloudflare Workers plan (100,000 requests/day) is far more than this
needs, especially with the 30-second edge cache.
