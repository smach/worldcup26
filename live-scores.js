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

// Format the live match clock, e.g. "80'" or "45+2'". Returns "" when the
// minute is unavailable, so callers can append it unconditionally. Mirrors
// R clock_label(). `injury` is the added/stoppage minutes (missing or 0 = none).
function clockLabel(minute, injury) {
  if (isMissing(minute)) return "";
  return !isMissing(injury) && injury > 0 ? `${minute}+${injury}'` : `${minute}'`;
}

// Build the human-readable scoreline for one match (live-mode rules).
//   { status, home, away, homePk, awayPk, utcDate, minute, injuryTime, now }
export function computeScoreDisplay({
  status,
  home,
  away,
  homePk,
  awayPk,
  utcDate,
  minute,
  injuryTime,
  now = new Date(),
} = {}) {
  if (isMissing(status)) return "";

  const hasScore = !isMissing(home) && !isMissing(away);
  const hasPk = !isMissing(homePk) && !isMissing(awayPk);
  const d = toDate(utcDate);
  const nowDate = toDate(now) ?? new Date();
  const inPast = d !== null && d < nowDate;

  if (LIVE_STATUSES.has(status)) {
    const clock = clockLabel(minute, injuryTime);
    if (hasScore) {
      const inner = clock ? `live ${clock}` : "live";
      return `${home}${DASH}${away} (${inner})`;
    }
    return clock ? `in progress (${clock})` : "in progress";
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
      minute: e.minute,
      injuryTime: e.injuryTime,
      now,
    });
    return {
      ...m,
      status: e.status,
      home_score: e.home,
      away_score: e.away,
      home_pk: e.homePk,
      away_pk: e.awayPk,
      minute: e.minute,
      injury_time: e.injuryTime,
      score_display,
    };
  });
}

// The knockout bracket, in order, for the "Knockout stage" tab.
//
// The football-data.org API returns each knockout fixture with its `stage`
// (LAST_32 … FINAL) but no bracket linkage and a null team for any slot not yet
// decided — so we present the rounds as ordered columns, not a connector tree.
// THIRD_PLACE is returned on its own so the page can place it beside the final.
const KO_ROUND_ORDER = ["LAST_32", "LAST_16", "QUARTER_FINALS", "SEMI_FINALS", "FINAL"];
const KO_ROUND_LABELS = {
  LAST_32: "Round of 32",
  LAST_16: "Round of 16",
  QUARTER_FINALS: "Quarter-finals",
  SEMI_FINALS: "Semi-finals",
  FINAL: "Final",
  THIRD_PLACE: "Third-place playoff",
};

// Sort knockout matches within a round by kickoff. Rows carry either a Date in
// `utc_date` (the page) or an ISO string in `utc_date_str` (raw data); fall back
// gracefully so the helper works in both, and on either field being absent.
function koKickoffMs(m) {
  const d = toDate(m.utc_date ?? m.utc_date_str);
  return d === null ? Infinity : d.getTime();
}

// Group the match array into the ordered knockout rounds.
//
//   matches  array of match objects (each with `stage` and a kickoff field)
//
// Returns { rounds, thirdPlace } where `rounds` is always the five main rounds
// in bracket order (each { stage, label, matches }, possibly empty) and
// `thirdPlace` is that single round object or null. Group-stage and
// stage-less rows are excluded; null-team rows are kept (they render as TBD).
export function knockoutRounds(matches) {
  const src = Array.isArray(matches) ? matches : [];
  const byStage = new Map();
  for (const m of src) {
    if (m == null) continue;
    const s = m.stage;
    if (s == null || s === "GROUP_STAGE") continue;
    if (!byStage.has(s)) byStage.set(s, []);
    byStage.get(s).push(m);
  }
  for (const list of byStage.values()) {
    list.sort((a, b) => koKickoffMs(a) - koKickoffMs(b));
  }

  const rounds = KO_ROUND_ORDER.map((stage) => ({
    stage,
    label: KO_ROUND_LABELS[stage],
    matches: byStage.get(stage) ?? [],
  }));

  const thirdMatches = byStage.get("THIRD_PLACE") ?? [];
  const thirdPlace =
    thirdMatches.length > 0
      ? { stage: "THIRD_PLACE", label: KO_ROUND_LABELS.THIRD_PLACE, matches: thirdMatches }
      : null;

  return { rounds, thirdPlace };
}
