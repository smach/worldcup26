test_that("resolve_team() matches exact names", {
  use_fixtures()
  hit <- resolve_team("Brazil")
  expect_equal(hit$name, "Brazil")
})

test_that("resolve_team() matches three-letter codes", {
  use_fixtures()
  expect_equal(resolve_team("USA")$name, "United States")
  expect_equal(resolve_team("BRA")$name, "Brazil")
})

test_that("resolve_team() is case- and punctuation-insensitive", {
  use_fixtures()
  expect_equal(resolve_team("united states")$name, "United States")
  expect_equal(resolve_team("U.S.A.")$name, "United States")
})

test_that("resolve_team() strips accents", {
  use_fixtures()
  expect_equal(resolve_team("México")$name, "Mexico")
})

test_that("resolve_team() honours the alias table", {
  use_fixtures()
  expect_equal(resolve_team("Korea")$name, "South Korea")
  expect_equal(resolve_team("Cape Verde")$name, "Cape Verde Islands")
  expect_equal(resolve_team("Czech Republic")$name, "Czechia")
})

test_that("resolve_team() falls back to substring match", {
  use_fixtures()
  expect_equal(resolve_team("herzegovina")$name, "Bosnia-Herzegovina")
})

test_that("resolve_team() errors when nothing matches", {
  use_fixtures()
  expect_error(resolve_team("Atlantis"), "No team matching")
})

test_that("resolve_team() errors when input is empty or NA", {
  use_fixtures()
  expect_error(resolve_team(""), "non-empty")
  expect_error(resolve_team(NA_character_), "non-empty")
})

test_that("normalise_name() handles accents and punctuation", {
  expect_equal(normalise_name("Côte d'Ivoire"), "cotedivoire")
  expect_equal(normalise_name("São Tomé"), "saotome")
  expect_equal(normalise_name("U.S.A."), "usa")
})
