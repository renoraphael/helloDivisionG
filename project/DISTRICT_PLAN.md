# Hello District 87: agreed plan and rules

Decided with the owner on 20 November 2026. These are binding project decisions for every assistant (Claude, Codex, Grok, Antigravity or any other). Do not change, weaken or work around them without the owner's explicit approval in the current conversation. If a request seems to conflict with a rule here, stop and ask the owner.

## Goal

Scale Hello Division G (the owner's DTM project) to Hello Division K first, then to all of District 87, where the District Trio and senior district officers can see every division.

## Non-negotiable rules

### Privacy and data
1. **Never store street address.** CSV importers keep city only. Phone numbers are not stored unless the owner decides otherwise. Unneeded columns are removed in the browser before upload.
2. **Members never see member records outside their own scope.** Club information (name, schedule, venue, area, awards) is visible to everyone in the district.
3. **Personal tasks and projects are owner-only**, enforced by per-user row-level security, never through the shared division payload. Nobody else can read them, including the Division Director, ADs and district leaders.
4. **Privacy law priority:** Malaysia PDPA first (stricter), then Indonesia UU PDP. This means a privacy notice, deletion on request, and a retention rule for past members.
5. **Member photos on posters need the member's consent** (per-member setting).
6. **Guest details** (names, phone numbers collected at meetings) are either not stored, or kept only in that club with consent and short retention.
7. **Toastmasters member data is used for Toastmasters business only.**
8. Never put live member data in test fixtures, logs, commits or public files. Tests use synthetic records only.

### Identity and editing
9. **People are matched by Toastmasters member ID**, not by name. Clubs are identified by **TI club number** (names change, for example BTC to MBTC).
10. **Everything routine is editable in the app** by authorised users: nicknames, aliases, corrections, club details, role assignments. The owner must not depend on an AI assistant for routine data updates.
11. **Imports never overwrite manual fields** (nicknames, aliases, photo, pronunciation, notes). If a hand-corrected TI field differs on the next import, the app asks ("keep yours or take TI's?") instead of overwriting.
12. **Every edit records who and when, and can be undone.**
13. **Freshest data wins.** Each import records its "as of" date per club. An older export cannot overwrite newer data, whoever uploads it.
14. **Scope-limited imports.** A Division Director or Area Director uploading a wider export only applies rows inside their own division or area.
15. **One person can hold memberships and roles in several clubs and divisions.** Access is the sum of their roles. Nothing may assume one person = one club = one division.

### Roles and access (enforced in the database, never only hidden in the UI)

| Role | Member records visible | Can edit |
|---|---|---|
| Member | Own | Own profile (nickname, aliases, photo, pronunciation) |
| Club officer | Own club | Own club's members and club details |
| Area Director | Own area | Own area, including roles in it |
| Division Director | Own division | Own division, including roles in it |
| PRM, FM, LM (SDOs) | Roll-ups only | Their own area of work |
| Administration Manager (AM) | All | Trio-like access (administration) |
| District Trio (DD, PQD, CGD) | All | Everything, including district-scope items |
| Alignment Chair (under PQD, CGD or SDO) | As assigned | Club realignment |
| Maintainer | All, with every access logged | System administration |

- Other PQD and CGD team roles are reviewed manually by the owner before any access is granted.
- **Maintainer** is a system role held by the owner. It is not an officer role and does **not** expire on 1 July. It can later be shared with a second admin.
- Two-step sign-in for Trio and AM is on the roadmap.

### Program year, terms and realignment
16. **The Toastmasters year runs 1 July to 30 June.** Club → area → division alignment is stored **per program year**, so history is never recounted into the wrong division.
17. **Roles have terms** (for example "AD G4, 2026–27"). A **transition window** opens on 15 May or on the first day of the District conference (DCM/DECM). From then, incoming officers can be entered in advance. They take over automatically on 1 July, and outgoing officers drop back to member. The maintainer role is exempt.
18. **Realignment** can be decided after the DCM/DECM. A district-level tool lets you draft next year's alignment, preview its impact, approve it and apply it on 1 July. It also handles mid-year charters and closures. Authority: Trio, AM and the Alignment Chair.
19. **District distinguished criteria are their own**, set per program year, and never derived from division or area results.

### Time, money and language
20. **Time zone per club.** Malaysian divisions use MYT only; Indonesian clubs use WIB, WITA or WIT. Every event time carries its zone.
21. **Currency per club** (IDR, MYR, BND).

### Community tab and templates
22. **Club poster and agenda designs are the property of each club.** They are confidential to their club (Division G only for now) and must be delivered as protected files, never bundled into code that other divisions download.
23. Other divisions get a **basic set only**: the half-half poster and similar generic layouts, plus 3–4 agenda formats with the least resemblance to any club's design. The BTC style counts as generic.

### Meetings, offline and ballots
24. **The timer and ballot must work fully offline** and reconnect and sync automatically when signal returns. Each vote carries its own ID, so a vote sent twice is counted once.
25. **Votes are anonymous.** A vote is never stored against a member's name, including in logs.
26. **Meeting mode needs no sign-in.** A one-time meeting code or QR, valid for one meeting for about 24 hours, opens only that meeting's timer and ballot. It exposes no member data beyond names already on that meeting's agenda.
27. Roadmap: the ballot count is visible only to that meeting's assigned ballot counter, the VPE and the Toastmaster of the Meeting.

### Engineering safety
28. **Test environment first.** A separate Supabase project with synthetic data. Changes are tried there before production.
29. **Automatic access tests before every release (priority).** A script signs in as each role and confirms what it can and cannot read or edit. A failing access test blocks the release.
30. **Release rollback.** The previous app files stay available, and switching back is one step.
31. **Production data migration is done last and reversibly.** The old shared record (`hdg_sync_state`) and its revision history stay untouched until the new tables have been proven equal and the owner approves the switch.
32. **Error reports reach the maintainer** through a maintainer-only Reports page, grouped by error. Reports never contain member data.
33. Simultaneous edits must never overwrite each other (per-record tables, not one shared payload).

### Ownership and continuity
34. Accounts (GitHub, Supabase) move to district ownership, with the owner as admin and at least one tested second admin.
35. Secrets live in a district-controlled password manager, never in chat, code or commits.
36. A handover pack and a yearly May–June handover checklist are maintained. The repository needs an explicit licence decision.
37. The tool is presented as an **unofficial District 87 tool**, follows TI brand rules, and needs District Executive Committee approval before district-wide rollout.

## Audience now
District leaders plus members the owner approves: under 50 people, or under 100 including all district leaders. Opening to all members, and funding, are the district's decision.

## Phases

**Phase 0: foundation.** Division G keeps working throughout.
1. Test environment.
2. Automatic access tests.
3. Per-record tables: clubs, people, memberships, alignment per year, roles with terms, division config.
4. Access rules by scope.
5. Manual fields and edit history.
6. Time zone and currency per club.
7. Move Division G onto the new tables (last, reversible, owner-approved switch).
8. Offline app with offline timer and ballot, plus meeting mode.
9. Error reports to the maintainer.
10. One-step release rollback.

**Phase 1: Hello Division K.** The two CSV importers (membership roster, club officers), the template split (basic set vs protected club designs), the TI dashboard scraper with a manual fallback, and Division K onboarding.

**Phase 2: District 87.** District roll-up, district scorecard, district calendar, leadership directory, realignment tool, and Trio, AM and SDO views.

**Onboarding.** A good onboarding screen and per-role tutorials. Leaders change every year, so the "what to do on 1 July" guide is required.

## Roadmap (ready for, not built now)
- Self-service sign-up matched to the roster, password reset, and lapsed members losing access after a grace period.
- Two-step sign-in for Trio and AM.
- Caption generator for WhatsApp and Instagram versions of posters; WhatsApp-first sharing.
- A donations link to an outside page (the app never handles payments), framed as supporting the tool's hosting and checked with the district.
- Android app after iPhone, on the same backend and rules.
- Backups and full export, feedback button and help pages, and a fallback if the TI dashboard changes format.
- Splitting the app so phones load only the tabs they use.
- AD club-visit tracking.
- Privacy-friendly usage numbers for the DTM project.
- April and October renewal waves shown separately from members who left.
