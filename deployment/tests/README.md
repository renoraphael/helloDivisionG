# v484 synthetic browser checks

The fixture contains synthetic people and a public club identifier. The browser checks were run against the private connected build with all production Supabase endpoints intercepted by a local test transport. They check 17 behaviors, including all 84 poster SVG combinations. Do not inject the test script into the live website: it edits its test dataset.

The generated QA HTML contains the legacy private app and is deliberately not committed. Use a private local source copy for reproducing integration tests. Real authenticated end-to-end testing is a separate owner-assisted check.

## v487

The v487 suite adds poster control, title/subtitle, address, optional registration, fee and featured-person checks. 26/28 pass on the supplied source: the two failures document existing fee omissions in four layouts and long-contact truncation in Split editorial. All 17 cloud integration regressions pass. The app source was preserved rather than silently redesigned.

## v514

26/26 local browser checks passed with mocked Supabase transport, including 84 poster SVG combinations, shared saves, education/date parsing, meeting-order memory, and PNG alpha/JPEG import. Built-in app history migration remains in the private source. No production data was edited by tests.
