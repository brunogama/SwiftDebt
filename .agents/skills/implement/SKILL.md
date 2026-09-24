---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch. Do not commit directly to `main`: if the current branch is `main`, stop and ask the user to create or name a topic branch first. This repository releases from `main` and uses `feature/*`, `release/*`, and `hotfix/*` branches for work.
