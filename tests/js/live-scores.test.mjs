// Tests for live-scores.js — run with: node --test tests/js/
//
// These mirror tests/testthat/test-score.R so the JS port of score_display()
// stays faithful to the R original (with live = TRUE), plus coverage for the
// mergeLiveScores() overlay.

import { test } from "node:test";
import assert from "node:assert/strict";
import { computeScoreDisplay, mergeLiveScores } from "../../live-scores.js";

const FUTURE = "2026-07-01T00:00:00Z";
const PAST = "2026-06-12T00:00:00Z";
const NOW = new Date("2026-06-20T00:00:00Z");

// ---- computeScoreDisplay ---------------------------------------------------

test("FINISHED with a score is a dash-separated line", () => {
  assert.equal(computeScoreDisplay({ status: "FINISHED", home: 2, away: 1, now: NOW }), "2–1");
});

test("FINISHED with no score reports 'no score available yet'", () => {
  assert.equal(computeScoreDisplay({ status: "FINISHED", now: NOW }), "no score available yet");
});

test("Penalty shoot-out result is appended", () => {
  assert.equal(
    computeScoreDisplay({ status: "FINISHED", home: 1, away: 1, homePk: 4, awayPk: 3, now: NOW }),
    "1–1 (4–3 PK)"
  );
});

test("Live statuses with a score show a running scoreline", () => {
  assert.equal(computeScoreDisplay({ status: "IN_PLAY", home: 1, away: 0, now: NOW }), "1–0 (live)");
  assert.equal(computeScoreDisplay({ status: "PAUSED", home: 2, away: 2, now: NOW }), "2–2 (live)");
  assert.equal(computeScoreDisplay({ status: "EXTRA_TIME", home: 3, away: 1, now: NOW }), "3–1 (live)");
});

test("Live status before the first goal falls back to 'in progress'", () => {
  assert.equal(computeScoreDisplay({ status: "IN_PLAY", now: NOW }), "in progress");
  assert.equal(computeScoreDisplay({ status: "PENALTY_SHOOTOUT", now: NOW }), "in progress");
});

test("Live scoreline appends the match clock when a minute is available", () => {
  assert.equal(
    computeScoreDisplay({ status: "IN_PLAY", home: 1, away: 0, minute: 67, now: NOW }),
    "1–0 (live 67')"
  );
  assert.equal(
    computeScoreDisplay({ status: "IN_PLAY", home: 0, away: 0, minute: 80, now: NOW }),
    "0–0 (live 80')"
  );
});

test("Injury time is shown as minute+added", () => {
  assert.equal(
    computeScoreDisplay({ status: "IN_PLAY", home: 1, away: 1, minute: 45, injuryTime: 2, now: NOW }),
    "1–1 (live 45+2')"
  );
  // injuryTime of 0 means no stoppage time to show.
  assert.equal(
    computeScoreDisplay({ status: "IN_PLAY", home: 1, away: 1, minute: 45, injuryTime: 0, now: NOW }),
    "1–1 (live 45')"
  );
});

test("The clock rides along even before the first goal", () => {
  assert.equal(computeScoreDisplay({ status: "IN_PLAY", minute: 12, now: NOW }), "in progress (12')");
});

test("SCHEDULED/TIMED: future is blank, past is 'no score available yet'", () => {
  assert.equal(computeScoreDisplay({ status: "SCHEDULED", utcDate: FUTURE, now: NOW }), "");
  assert.equal(computeScoreDisplay({ status: "TIMED", utcDate: FUTURE, now: NOW }), "");
  assert.equal(
    computeScoreDisplay({ status: "SCHEDULED", utcDate: PAST, now: NOW }),
    "no score available yet"
  );
});

test("Off-pitch statuses are lower-cased", () => {
  assert.equal(computeScoreDisplay({ status: "POSTPONED", now: NOW }), "postponed");
  assert.equal(computeScoreDisplay({ status: "CANCELLED", now: NOW }), "cancelled");
  assert.equal(computeScoreDisplay({ status: "SUSPENDED", now: NOW }), "suspended");
});

test("Missing/unknown status is blank", () => {
  assert.equal(computeScoreDisplay({ status: null, now: NOW }), "");
  assert.equal(computeScoreDisplay({ status: undefined, now: NOW }), "");
  assert.equal(computeScoreDisplay({ status: "WEIRD", now: NOW }), "");
});

test("A zero score is not treated as missing", () => {
  assert.equal(computeScoreDisplay({ status: "IN_PLAY", home: 0, away: 0, now: NOW }), "0–0 (live)");
  assert.equal(computeScoreDisplay({ status: "FINISHED", home: 0, away: 0, now: NOW }), "0–0");
});

// ---- mergeLiveScores -------------------------------------------------------

const base = [
  { match_id: 1, utc_date: new Date("2026-06-15T18:00:00Z"), status: "TIMED", score_display: "" },
  { match_id: 2, utc_date: new Date("2026-06-15T21:00:00Z"), status: "TIMED", score_display: "" },
];

test("matching entry updates status, scores, and recomputes display", () => {
  const out = mergeLiveScores(base, [{ id: 1, status: "IN_PLAY", home: 1, away: 0 }], NOW);
  assert.equal(out[0].status, "IN_PLAY");
  assert.equal(out[0].home_score, 1);
  assert.equal(out[0].away_score, 0);
  assert.equal(out[0].score_display, "1–0 (live)");
  // unmatched row untouched
  assert.equal(out[1].status, "TIMED");
  assert.equal(out[1].score_display, "");
});

test("minute/injuryTime from the proxy flow into the recomputed display", () => {
  const out = mergeLiveScores(
    base,
    [{ id: 1, status: "IN_PLAY", home: 2, away: 1, minute: 45, injuryTime: 3 }],
    NOW
  );
  assert.equal(out[0].score_display, "2–1 (live 45+3')");
  assert.equal(out[0].minute, 45);
  assert.equal(out[0].injury_time, 3);
});

test("string ids from the proxy still match integer match_id", () => {
  const out = mergeLiveScores(base, [{ id: "2", status: "FINISHED", home: 3, away: 2 }], NOW);
  assert.equal(out[1].score_display, "3–2");
});

test("unknown ids are ignored", () => {
  const out = mergeLiveScores(base, [{ id: 999, status: "IN_PLAY", home: 5, away: 5 }], NOW);
  assert.deepEqual(out, base);
});

test("empty or non-array entries return the base array unchanged", () => {
  assert.equal(mergeLiveScores(base, [], NOW), base);
  assert.equal(mergeLiveScores(base, null, NOW), base);
  assert.equal(mergeLiveScores(base, undefined, NOW), base);
});

test("returns a new array and does not mutate inputs", () => {
  const snapshot = JSON.parse(JSON.stringify(base.map((m) => ({ ...m, utc_date: m.utc_date.toISOString() }))));
  const out = mergeLiveScores(base, [{ id: 1, status: "FINISHED", home: 2, away: 1 }], NOW);
  assert.notEqual(out, base);
  // original objects unchanged
  assert.equal(base[0].status, "TIMED");
  assert.equal(base[0].score_display, "");
  assert.deepEqual(
    base.map((m) => ({ ...m, utc_date: m.utc_date.toISOString() })),
    snapshot
  );
});
