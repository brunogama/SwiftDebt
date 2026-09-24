# Triage labels

Apply these labels to GitHub Issues in `brunogama/SwiftDebt` to make the next action visible.

| Label | Meaning |
| --- | --- |
| `needs-triage` | The issue has not been classified yet. |
| `needs-info` | The issue is blocked on missing information. |
| `ready-for-agent` | An agent can implement and verify the issue. |
| `ready-for-human` | The issue needs human review or a human-only decision. |
| `wontfix` | The issue is intentionally not planned. |

Use `gh issue edit <number> --repo brunogama/SwiftDebt --add-label <label>` to apply a label. Remove an obsolete action label when the issue moves to another state.
