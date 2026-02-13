# td-next: Determine Next Action

Run this prompt at the start of any session to determine what to work on.

## Instructions

1. First, check for issues awaiting your review:
   ```bash
   td reviewable
   ```

2. If reviewable issues exist:
   - Run `td show <id>` to see full context
   - Review the implementation (code changes, tests, etc.)
   - Run `td approve <id> -m "feedback"` OR `td reject <id> -m "issues found"`
   - **CRITICAL**: Reviews must be done in a DIFFERENT session than implementation

3. If nothing to review, find next work via critical path:
   ```bash
   td critical-path
   ```

4. Start the first issue under "START NOW" section:
   ```bash
   td usage --new-session
   td start <id>
   ```

5. While working, log progress:
   ```bash
   td log <id> "What you accomplished"
   ```

6. Before finishing, capture state:
   ```bash
   td handoff <id> --done "completed items" --remaining "todo items"
   ```

7. Submit for review:
   ```bash
   td review <id>
   ```

## Quick Decision Command

```bash
# Returns reviewable issues OR critical path start candidates
(td reviewable | grep -q . && td reviewable) || td critical-path | grep -A5 "START NOW"
```

## Session Hygiene

- Always `td usage --new-session` at conversation start
- Never approve your own work (td enforces this)
- Always `td handoff` before `td review`
- Use `td session "descriptive-name"` to label sessions
