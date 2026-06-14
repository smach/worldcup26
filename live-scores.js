// Pure helpers for the optional client-side "Update scores" overlay.
//
// Imported by index.qmd (Observable JS) and unit-tested with node --test
// (tests/js/live-scores.test.mjs). No DOM, no fetch, no Observable APIs in
// here so it stays testable in plain node.
//
// computeScoreDisplay() is a faithful port of R/score.R::score_display() with
// live = TRUE (the button only matters during live windows). Keep the two in
// sync; tests/js/live-scores.test.mjs mirrors tests/testthat/test-score.R.

const DASH = "–"; // en dash, matching the R side

const LIVE_STATUSES = new Set(["IN_PLAY", "PAUSED", "EXTRA_TIME", "PENALTY_SHOOTOUT"]);
const FINAL_STATUSES = new Set(["FINISHED", "AWARDED"]);
const INACTIVE_STATUSES = new Set(["CANCELLED", "POSTPONED", "SUSPENDED"]);

function isMissing(v) {
  return v === null || v === undefined || (typeof v === "number" && Number.isNaN(v));
}

function toDate(v) {
  if (v instanceof Date) return v;
  if (v === null || v === undefined) return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

// Build the human-readable scoreline for one match (live-mode rules).
//   { status, home, away, homePk, awayPk, utcDate, now }
export function computeScoreDisplay({
  status,
  home,
  away,
  homePk,
  awayPk,
  utcDate,
  now = new Date(),
} = {}) {
  if (isMissing(status)) return "";

  const hasScore = !isMissing(home) && !isMissing(away);
  const hasPk = !isMissing(homePk) && !isMissing(awayPk);
  const d = toDate(utcDate);
  const nowDate = toDate(now) ?? new Date();
  const inPast = d !== null && d < nowDate;

  if (LIVE_STATUSES.has(status)) {
    return hasScore ? `${home}${DASH}${away} (live)` : "in progress";
  }
  if (FINAL_STATUSES.has(status)) {
    if (!hasScore) return "no score available yet";
    let out = `${home}${DASH}${away}`;
    if (hasPk) out += ` (${homePk}${DASH}${awayPk} PK)`;
    return out;
  }
  if (INACTIVE_STATUSES.has(status)) {
    return String(status).toLowerCase();
  }
  if (status === "SCHEDULED" || status === "TIMED") {
    return inPast ? "no score available yet" : "";
  }
  return "";
}

// Overlay fresh scores from the proxy onto the build-time match array.
//
//   baseMatches  array of match objects (each with `match_id`, `utc_date`)
//   liveEntries  array of slim entries from the proxy ({id, status, home,
//                away, homePk, awayPk, utcDate})
//   now          reference time for past/future judgement
//
// Returns a NEW array (same length/order). Matched rows get updated status,
// scores, and a recomputed `score_display`; unmatched rows are returned
// unchanged. Unknown ids in liveEntries are ignored. An empty liveEntries
// returns the base rows untouched, so the page renders identically when the
// feature is off.
export function mergeLiveScores(baseMatches, liveEntries, now = new Date()) {
  if (!Array.isArray(liveEntries) || liveEntries.length === 0) {
    return baseMatches;
  }
  const byId = new Map();
  for (const e of liveEntries) {
    if (e && e.id !== null && e.id !== undefined) byId.set(Number(e.id), e);
  }

  return baseMatches.map((m) => {
    const e = byId.get(Number(m.match_id));
    if (!e) return m;
    const score_display = computeScoreDisplay({
      status: e.status,
      home: e.home,
      away: e.away,
      homePk: e.homePk,
      awayPk: e.awayPk,
      utcDate: m.utc_date ?? m.utc_date_str,
      now,
    });
    return {
      ...m,
      status: e.status,
      home_score: e.home,
      away_score: e.away,
      home_pk: e.homePk,
      away_pk: e.awayPk,
      score_display,
    };
  });
}
