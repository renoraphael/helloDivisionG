# Shared project entry point

Repository: https://github.com/renoraphael/helloDivisionG
Website: https://renoraphael.github.io/helloDivisionG/

Use this project with any coding assistant. GitHub stores tracked code, instructions, history, branches, and PRs. It does not share chat memory or grant access to another tool. Each assistant needs its own authorized GitHub connection or a checkout on the owner's Mac.

## Supabase environments

- **Production · Singapore** is `ovmdhkrkogivlvjnbqpj` (`ap-southeast-1`). The dashboard name is **Hello Division G**.
- **Synthetic test · Singapore** is **Hello Division G Synthetic Test**, `oenawxeckerazwhvlpse` (`ap-southeast-1`). Seed invented data only.
- **Paused fallback · Seoul** is **Hello Division G (Seoul, retired)**, `bhbgusdxqbjwsdlzhurb` (`ap-northeast-2`). Keep it paused during the production stability period. A final verified backup and explicit owner approval are required before deleting it.
- The 27 November 2026 decision retired migration 013, migration 014, and the separate Division K build from the production release path. Division K uses the shared app. The original SQL and build files remain for synthetic tests and reference.

## Start each task
1. Read AGENTS.md, project/ARCHITECTURE.md, project/DISTRICT_PLAN.md (binding agreed rules), and project/HANDOFF.md.
2. Inspect the current branch, commit, working changes, and open PRs. Pull only after ensuring that existing local work is safe.
3. Create a task branch. Work on the requested task, then verify the relevant behavior.
4. Update the handoff, commit tracked changes, push the branch, and open a PR. Record deployment separately.

Use project/AI_START_PROMPT.md as the initial message in Claude, Grok, Antigravity, Codex, or another assistant. File autodiscovery differs between tools; explicitly tell each tool to read these files. CLAUDE.md is an additional entry pointer, not a separate set of rules.

## Working locally
The owner has a separate shared checkout with private-app/v632.html supplied locally and excluded from Git. Local coding tools can use that same folder sequentially. Simultaneous work needs separate working copies and task branches. Do not assume browser-only assistants can edit local files or push commits: connect their own GitHub access or have them return a patch.

## Important current gap
A public clone contains the launcher and access/sync code, but not the complete legacy v632 app source. Its member-bearing HTML is protected in Supabase. Full GitHub-only collaboration on the entire app requires separating legacy embedded data from executable source. Do not "solve" this by publishing the private HTML.

An existing draft PR contains the database and iPhone setup on setup/central-database-plan. Check its status before duplicating work. Main is the live launcher branch. Do not assume a draft branch has been merged or deployed.
