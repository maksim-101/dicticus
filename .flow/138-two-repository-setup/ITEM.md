---
id: 138
title: two-repository-setup
status: planned
size:
assignee: none
created: 2026-11-21
why: the owner wants this repository as a private workshop and a clean public repository for what is published (asked 2026-11-17, confirmed 2026-11-21); after the current review and optimisation work, by the owner's order
waiting_until:
shipped:
links:
---

# This repository becomes the private workshop and a new public repository carries only what is published, with updates and downloads unbroken

Requested through the flow maintainer session (flow-43). At the brief: read flow's `references/publish.md` (flow 0.10.9+) and the CHANGELOG 0.10.6-0.10.10, re-check flow-43's facts of 2026-11-17 (public repo, 0 forks, GitHub Pages from gh-pages; `SUFeedURL` in `macOS/Dicticus/Info.plist` points at the github.io appcast, and each appcast entry downloads from this repository's releases, so making it private first breaks updates), ask the owner who the one or two contributors are and what access they need, and report to flow-43 what publish.md covered and the route chosen. Routes to settle: keep the public name (rename this one first, then create the public one under the old name, moving site, appcast and DMGs) or a new public name with a bridging release; the PUBLISH.md allowlist and a publish.py dry run on main; public side serving feed and downloads, checked signed-out, before the visibility switch; the rename, switch and creation are owner steps. iOS (TestFlight) does not depend on the repository. The licence choice belongs here too (no LICENSE file yet; copied MIT code needs attribution).
