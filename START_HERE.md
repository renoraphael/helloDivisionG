# Shared project entry point

Repository: https://github.com/renoraphael/helloDivisionG
Website: https://renoraphael.github.io/helloDivisionG/

Use this project with any coding assistant. GitHub stores tracked code, instructions, history, branches, and PRs. It does not share chat memory or grant access to another tool. Each assistant needs its own authorized GitHub connection or a checkout on the owner's Mac.

## Start each task
1. Read AGENTS.md, project/ARCHITECTURE.md, and project/HANDOFF.md.
2. Inspect the current branch, commit, working changes, and open PRs. Pull only after ensuring that existing local work is safe.
3. Create a task branch. Work on the requested task, then verify the relevant behavior.
4. Update the handoff, commit tracked changes, push the branch, and open a PR. Record deployment separately.

Use project/AI_START_PROMPT.md as the initial message in Claude, Grok, Antigravity, Codex, or another assistant. File autodiscovery differs between tools; explicitly tell each tool to read these files. CLAUDE.md is an additional entry pointer, not a separate set of rules.

## Working locally
The owner has a separate shared checkout with private-app/v475.html supplied locally and excluded from Git. Local coding tools can use that same folder sequentially. Simultaneous work needs separate working copies and task branches. Do not assume browser-only assistants can edit local files or push commits: connect their own GitHub access or have them return a patch.

## Important current gap
A public clone contains the launcher and access/sync code, but not the complete legacy v475 app source. Its member-bearing HTML is protected in Supabase. Full GitHub-only collaboration on the entire app requires separating legacy embedded data from executable source. Do not "solve" this by publishing the private HTML.

An existing draft PR contains the database and iPhone setup on setup/central-database-plan. Check its status before duplicating work. Main is the live launcher branch. Do not assume a draft branch has been merged or deployed.
