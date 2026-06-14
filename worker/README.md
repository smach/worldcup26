# worldcup26 live-score proxy (Cloudflare Worker)

A tiny serverless proxy that lets the static [worldcup26 Quarto
site](../index.qmd) refresh live scores from a button **without** rebuilding the
site and **without** exposing the football-data.org API key in the browser.

## Why this exists

The site is published on **GitHub Pages** and refreshed by a **GitHub Actions**
workflow that runs the R package in a container. That's perfect for a periodic
snapshot, but it's slow: every refresh spins up a container and installs R +
Quarto + package dependencies before it can re-render. During a live match,
waiting minutes for that just to see the latest score is painful.

This Worker is the fast path. The published page gets an **"Update scores"**
button that fetches the current scores directly — no Actions run, no container,
no R — so the scoreline updates in a second or two. The catch is that
football-data.org needs a secret API key, and **a public static page can't hold
a secret** (anything in the page or its JavaScript is visible to every visitor).
So instead of calling the API from the browser, the button calls this Worker,
which holds the key server-side as a Cloudflare **secret** and returns only the
scores.

The R/Actions pipeline still runs as the authoritative source; the button is
just a fast live overlay on top of the last published snapshot.

This is **optional**. If you don't deploy it (and don't set
`WORLDCUP26_SCORE_PROXY_URL` when rendering the site), the site works exactly as
before — there's simply no "Update scores" button. The R rebuild pipeline is
unaffected either way.

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
   Pages** → **Create application**. When asked how to start, choose **Start with
   Hello World** (not "Connect GitHub/GitLab", a template, or "Upload static
   files"). Name it `worldcup26-scores` and click **Deploy** — this deploys the
   throwaway starter, which you'll replace next.

2. **Paste in the code.** Click **Edit code**. Select everything in the editor
   and delete it, then open [`src/index.js`](src/index.js) from this folder,
   copy the whole file, paste it in, and click **Deploy** (top right).

   At this point loading the Worker's URL returns `{"error":"proxy not
   configured"}` — that's expected; it just means the key isn't set yet.

3. **Add the API key + variables.** Open the Worker's **Settings** tab →
   **Variables and Secrets** → **+ Add**. Each entry has a **Type** dropdown:
   - **Type: Secret** — name **`FOOTBALL_DATA_API_KEY`**, value = your paid
     football-data.org key. (Secrets are write-only — the value never shows again
     and never appears in the response.)
   - **Type: Text** — name **`ALLOWED_ORIGINS`**, value
     `https://smach.github.io,http://localhost:4321,http://127.0.0.1:4321`
     (use your own GitHub Pages origin if you forked the repo).
   - **Type: Text** — name **`CACHE_TTL_SECONDS`**, value `30`.

4. **Deploy again** so the secret and variables take effect (Cloudflare prompts
   you to deploy after editing variables; if not, hit **Deploy** in the editor).

5. **Grab your URL.** The Worker's overview page shows it, e.g.
   `https://worldcup26-scores.YOUR-SUBDOMAIN.workers.dev`. Paste it into a
   browser — you should now see JSON with a `matches` array and **no key
   anywhere**.

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
