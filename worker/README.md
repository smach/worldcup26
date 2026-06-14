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

You need a free [Cloudflare account](https://dash.cloudflare.com/sign-up). The
free Workers plan (100,000 requests/day) is far more than this needs.

---

## Deploy — Option A: Cloudflare dashboard (recommended, no install)

No Node, no npm, no command line. **This is the easiest path, especially on
Windows**, where installing the `wrangler` CLI can fail on native build
dependencies. Everything below is point-and-click in your browser.

1. **Create the Worker.** Go to <https://dash.cloudflare.com> → **Workers &
   Pages** → **Create** → **Create Worker**. Name it `worldcup26-scores` and
   click **Deploy** (this deploys the throwaway "Hello World" starter).

2. **Paste in the code.** Click **Edit code**. Select everything in the editor
   and delete it, then open [`src/index.js`](src/index.js) from this folder,
   copy the whole file, paste it in, and click **Deploy**.

3. **Add the API key as a secret.** Open the Worker's **Settings → Variables and
   Secrets**:
   - Under **Secrets**, **Add** one named **`FOOTBALL_DATA_API_KEY`** with your
     paid football-data.org key as the value. (Secrets are write-only — the value
     never shows again and never appears in the response.)

4. **Add two plain variables** (same screen, under **Variables**):
   - **`ALLOWED_ORIGINS`** =
     `https://smach.github.io,http://localhost:4321,http://127.0.0.1:4321`
     (replace the GitHub Pages origin with your own if you forked the repo)
   - **`CACHE_TTL_SECONDS`** = `30`

5. **Redeploy** so the secret and variables take effect (Deployments → redeploy,
   or just hit **Deploy** in the editor again).

6. **Grab your URL.** The Worker's overview page shows it, e.g.
   `https://worldcup26-scores.YOUR-SUBDOMAIN.workers.dev`. Paste it into a
   browser — you should see JSON with a `matches` array and **no key anywhere**.

That URL is what you put in `WORLDCUP26_SCORE_PROXY_URL` ([below](#turn-the-button-on)).

---

## Deploy — Option B: Wrangler CLI (if you prefer the command line)

Requires [Wrangler](https://developers.cloudflare.com/workers/wrangler/) and a
working Node/npm install. On Windows this can fail on optional native
dependencies (e.g. `sharp`) or PATH issues for npm's child processes — if so, use
**Option A** instead; it does the exact same thing.

```bash
cd worker

# 1. Log in (opens a browser once).
npx wrangler login

# 2. Store the API key as a secret. FOOTBALL_DATA_API_KEY here is the secret's
#    NAME, not its value — do NOT put the key on this line. After you press
#    Enter, wrangler prompts "Enter a secret value:"; paste your PAID key there.
#    The value is hidden and never stored in shell history or any file.
npx wrangler secret put FOOTBALL_DATA_API_KEY

# 3. (Optional) edit wrangler.toml: set ALLOWED_ORIGINS to your Pages origin.

# 4. Deploy.
npx wrangler deploy
```

`wrangler deploy` prints the public URL, e.g.
`https://worldcup26-scores.YOUR-SUBDOMAIN.workers.dev`. The `ALLOWED_ORIGINS` and
`CACHE_TTL_SECONDS` values come from `wrangler.toml` in this folder.

To preview locally before deploying:

```bash
cd worker
npx wrangler dev   # serves on http://localhost:8787
# In another shell:
curl -s -H "Origin: http://localhost:4321" http://localhost:8787 | head
```

Confirm the JSON shape, that no key appears anywhere in the output, and that a
request with a disallowed `Origin` is rejected with 403.

---

## Turn the button on

Set your Worker URL as `WORLDCUP26_SCORE_PROXY_URL` wherever the site is rendered.
Leaving it unset keeps the button off and the site unchanged.

- **Local preview:** add to `~/.Renviron`
  (`WORLDCUP26_SCORE_PROXY_URL=https://worldcup26-scores.YOUR-SUBDOMAIN.workers.dev`)
  and restart R.
- **GitHub Pages build:** add a repository **variable** named
  `WORLDCUP26_SCORE_PROXY_URL` (Settings → Secrets and variables → Actions →
  **Variables**), set to the same URL. `.github/workflows/publish.yml` already
  passes it into the render environment.

## Updating the code later

If you change `src/index.js`, re-deploy the same way you first deployed: paste
the new code in the dashboard editor and **Deploy** (Option A), or run
`npx wrangler deploy` (Option B). Secrets and variables persist across deploys —
you only set them once.
