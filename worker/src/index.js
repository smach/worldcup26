// Cloudflare Worker: live-score proxy for the worldcup26 Quarto site.
//
// Why this exists: the static GitHub Pages site can't call football-data.org
// directly without exposing the API key in the browser. This Worker holds the
// key as a Cloudflare *secret*, fetches the World Cup matches, slims the
// payload to just what the page needs to patch scores, and serves it with CORS
// headers so the "Update scores" button can fetch it.
//
// Rate-limit protection: responses are cached at the edge for CACHE_TTL_SECONDS,
// so many visitors clicking the button in the same window share ONE upstream
// API call. The key never appears in any response body or header we return.
//
// Setup (see worker/README.md):
//   wrangler secret put FOOTBALL_DATA_API_KEY   # paste the (paid) key
//   wrangler deploy
//
// Config via wrangler.toml [vars]:
//   ALLOWED_ORIGINS     comma-separated list of allowed page origins
//   CACHE_TTL_SECONDS   edge + browser cache lifetime (default 30)

const UPSTREAM = "https://api.football-data.org/v4/competitions/WC/matches";

const DEFAULT_ALLOWED = [
  "https://smach.github.io",
  "http://localhost:4321", // quarto preview default port
  "http://127.0.0.1:4321",
];

export default {
  async fetch(request, env, ctx) {
    const allowed = parseOrigins(env.ALLOWED_ORIGINS) ?? DEFAULT_ALLOWED;
    const origin = request.headers.get("Origin") || "";
    const allowOrigin = allowed.includes(origin) ? origin : null;
    const ttl = Number(env.CACHE_TTL_SECONDS) || 30;

    // CORS preflight.
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders(allowOrigin) });
    }

    if (request.method !== "GET") {
      return json({ error: "method not allowed" }, 405, allowOrigin, ttl);
    }

    // Browsers without a matching Origin are rejected; this is soft protection
    // against the public URL being reused by arbitrary other sites.
    if (origin && !allowOrigin) {
      return json({ error: "origin not allowed" }, 403, null, ttl);
    }

    if (!env.FOOTBALL_DATA_API_KEY) {
      return json({ error: "proxy not configured" }, 500, allowOrigin, ttl);
    }

    // Edge cache, keyed on a stable internal URL (not the visitor's request, so
    // every visitor shares one cached entry regardless of their Origin).
    const cache = caches.default;
    const cacheKey = new Request("https://worldcup26-proxy/scores", { method: "GET" });
    let upstreamPayload = await cache.match(cacheKey);

    if (!upstreamPayload) {
      let resp;
      try {
        resp = await fetch(UPSTREAM, {
          headers: {
            "X-Auth-Token": env.FOOTBALL_DATA_API_KEY,
            "User-Agent": "worldcup26 score proxy (https://github.com/smach/worldcup26)",
          },
        });
      } catch (err) {
        return json({ error: "upstream fetch failed" }, 502, allowOrigin, ttl);
      }
      if (!resp.ok) {
        return json({ error: "upstream error", status: resp.status }, 502, allowOrigin, ttl);
      }
      const body = await resp.json();
      const slim = slimMatches(body);
      upstreamPayload = new Response(JSON.stringify(slim), {
        headers: { "Content-Type": "application/json", "Cache-Control": `max-age=${ttl}` },
      });
      // Store a clone in the edge cache; don't block the response on it.
      ctx.waitUntil(cache.put(cacheKey, upstreamPayload.clone()));
    }

    const data = await upstreamPayload.json();
    return json(data, 200, allowOrigin, ttl);
  },
};

// Reduce the upstream response to one small entry per match: only the fields
// the page needs to recompute a scoreline. Field names are chosen to match
// live-scores.js (id, status, home, away, homePk, awayPk, utcDate).
function slimMatches(body) {
  const matches = Array.isArray(body?.matches) ? body.matches : [];
  return {
    generated_utc: new Date().toISOString(),
    matches: matches.map((m) => ({
      id: m.id ?? null,
      status: m.status ?? null,
      home: m.score?.fullTime?.home ?? null,
      away: m.score?.fullTime?.away ?? null,
      homePk: m.score?.penalties?.home ?? null,
      awayPk: m.score?.penalties?.away ?? null,
      utcDate: m.utcDate ?? null,
    })),
  };
}

function parseOrigins(raw) {
  if (!raw) return null;
  const list = raw.split(",").map((s) => s.trim()).filter(Boolean);
  return list.length ? list : null;
}

function corsHeaders(allowOrigin) {
  const h = {
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    Vary: "Origin",
  };
  if (allowOrigin) h["Access-Control-Allow-Origin"] = allowOrigin;
  return h;
}

function json(obj, status, allowOrigin, ttl) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Cache-Control": `public, max-age=${ttl}`,
      ...corsHeaders(allowOrigin),
    },
  });
}
