// Tests for live-scores.js — run with: node --test tests/js/
//
// These mirror tests/testthat/test-score.R so the JS port of score_display()
// stays faithful to the R original (with live = TRUE), plus coverage for the
// mergeLiveScores() overlay.

import { test } from "node:test";
import assert from "node:assert/strict";
import { computeScoreDisplay, mergeLiveScores, knockoutRounds } from "../../live-scores.js";

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

// ---- knockoutRounds --------------------------------------------------------

// One match per knockout stage plus a couple of group rows, deliberately out of
// kickoff order within the round so the sort is exercised.
const koMatches = [
  { match_id: 10, stage: "GROUP_STAGE", group: "GROUP_A", utc_date: new Date("2026-06-12T18:00:00Z") },
  { match_id: 11, stage: "GROUP_STAGE", group: "GROUP_B", utc_date: new Date("2026-06-13T18:00:00Z") },
  { match_id: 20, stage: "LAST_32", home_team: "Brazil", away_team: "Korea", utc_date: new Date("2026-06-28T23:00:00Z") },
  { match_id: 21, stage: "LAST_32", home_team: "France", away_team: "Senegal", utc_date: new Date("2026-06-28T19:00:00Z") },
  { match_id: 30, stage: "LAST_16", home_team: null, away_team: null, utc_date: new Date("2026-07-04T19:00:00Z") },
  { match_id: 40, stage: "QUARTER_FINALS", home_team: null, away_team: null, utc_date: new Date("2026-07-10T19:00:00Z") },
  { match_id: 50, stage: "SEMI_FINALS", home_team: null, away_team: null, utc_date: new Date("2026-07-14T19:00:00Z") },
  { match_id: 60, stage: "THIRD_PLACE", home_team: null, away_team: null, utc_date: new Date("2026-07-18T19:00:00Z") },
  { match_id: 70, stage: "FINAL", home_team: null, away_team: null, utc_date: new Date("2026-07-19T19:00:00Z") },
];

test("knockoutRounds returns the five main rounds in bracket order", () => {
  const { rounds } = knockoutRounds(koMatches);
  assert.deepEqual(
    rounds.map((r) => r.stage),
    ["LAST_32", "LAST_16", "QUARTER_FINALS", "SEMI_FINALS", "FINAL"]
  );
  assert.deepEqual(
    rounds.map((r) => r.label),
    ["Round of 32", "Round of 16", "Quarter-finals", "Semi-finals", "Final"]
  );
});

test("knockoutRounds excludes group-stage and keeps null-team (TBD) rows", () => {
  const { rounds } = knockoutRounds(koMatches);
  const ids = rounds.flatMap((r) => r.matches.map((m) => m.match_id));
  assert.ok(!ids.includes(10) && !ids.includes(11)); // group rows dropped
  const r16 = rounds.find((r) => r.stage === "LAST_16");
  assert.equal(r16.matches.length, 1);
  assert.equal(r16.matches[0].home_team, null); // TBD row preserved
});

test("knockoutRounds sorts matches within a round by kickoff", () => {
  const { rounds } = knockoutRounds(koMatches);
  const r32 = rounds.find((r) => r.stage === "LAST_32");
  assert.deepEqual(r32.matches.map((m) => m.match_id), [21, 20]); // 19:00 before 23:00
});

test("knockoutRounds separates the third-place playoff", () => {
  const { rounds, thirdPlace } = knockoutRounds(koMatches);
  assert.ok(rounds.every((r) => r.stage !== "THIRD_PLACE"));
  assert.equal(thirdPlace.stage, "THIRD_PLACE");
  assert.equal(thirdPlace.label, "Third-place playoff");
  assert.equal(thirdPlace.matches.length, 1);
});

test("knockoutRounds also sorts on the raw utc_date_str field", () => {
  const raw = [
    { match_id: 2, stage: "LAST_32", utc_date_str: "2026-06-28T23:00:00Z" },
    { match_id: 1, stage: "LAST_32", utc_date_str: "2026-06-28T19:00:00Z" },
  ];
  const { rounds } = knockoutRounds(raw);
  const r32 = rounds.find((r) => r.stage === "LAST_32");
  assert.deepEqual(r32.matches.map((m) => m.match_id), [1, 2]);
});

test("knockoutRounds on empty/groups-only input yields empty rounds and no third place", () => {
  const empty = knockoutRounds([]);
  assert.equal(empty.rounds.length, 5);
  assert.ok(empty.rounds.every((r) => r.matches.length === 0));
  assert.equal(empty.thirdPlace, null);

  const groupsOnly = knockoutRounds(koMatches.filter((m) => m.stage === "GROUP_STAGE"));
  assert.ok(groupsOnly.rounds.every((r) => r.matches.length === 0));
  assert.equal(groupsOnly.thirdPlace, null);
});
