---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Run typechecking regularly, single test files regularly, and the full test suite once at the end.

Once done, use /code-review to review the work.

Commit your work to the current branch. Do not commit to `main` or `dev`: if the current branch is `main` or `dev`, stop and ask the user to create or name a topic branch first, since this repository requires all changes to reach `dev` through a pull request.
