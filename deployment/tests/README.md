# v484 synthetic browser checks

The fixture contains synthetic people and a public club identifier. The browser checks were run against the private connected build with all production Supabase endpoints intercepted by a local test transport. They check 17 behaviors, including all 84 poster SVG combinations. Do not inject the test script into the live website: it edits its test dataset.

The generated QA HTML contains the legacy private app and is deliberately not committed. Use a private local source copy for reproducing integration tests. Real authenticated end-to-end testing is a separate owner-assisted check.
