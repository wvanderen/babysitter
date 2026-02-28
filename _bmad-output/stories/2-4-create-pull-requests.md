# Story 2.4: Create Pull Requests

Status: done

<!-- BMAD-TD Integration: This story is synced with td task td-e31891 -->

## td Integration

- **td Epic**: `td-3b16e3`
- **td Task**: `td-e31891`
- **Status**: closed
- **Last Sync**: 2026-02-27T19:30:00Z

---

## Story

As a user,
I want babysitter to create PRs when workflows complete,
So that changes are ready for human review.

## Acceptance Criteria

1. **AC1: PR Creation Trigger**
   - Given a workflow completes successfully
   - When PR trigger is configured
   - Then a PR is created automatically

2. **AC2: PR Title and Body**
   - Given a workflow completes
   - When PR is created
   - Then title follows configured template
   - And body includes summary from workflow execution

3. **AC3: Labels**
   - Given labels are configured
   - When PR is created
   - Then labels are applied from template

4. **AC4: Reviewers**
   - Given reviewers are configured
   - When PR is created
   - Then reviewers are assigned if configured

## Tasks / Subtasks

- [x] Task 1: Implement Git PR module (AC: #1, #2, #3, #4) [td:td-964a43]
  - [x] 1.1: Create PR configuration schema in config
  - [x] 1.2: Implement PR template rendering
  - [x] 1.3: Implement create_pr/2 function
  - [x] 1.4: Add label and reviewer support
  - [x] 1.5: Integrate with workflow completion

- [x] Task 2: Add configuration options (AC: #1) [td:td-dc5cd9]
  - [x] 2.1: Add PR trigger settings to config
  - [x] 2.2: Add template support for title/body
  - [x] 2.3: Add labels and reviewers config

- [x] Task 3: Tests (AC: #1, #2, #3, #4) [td:td-6210cb]
  - [x] 3.1: Test PR creation with all fields
  - [x] 3.2: Test template rendering
  - [x] 3.3: Test configuration loading

## Dev Notes

### Architecture Context

From architecture.md:
- FR-6: Git integration - Configurable commit triggers, PR creation
- Location: `elixir/lib/babysitter/git/`

### Key Files Created/Modified

```
elixir/
├── lib/
│   └── babysitter/
│       ├── pr.ex              # EXISTING: Already implemented in prior story
│       ├── pr_trigger.ex      # NEW: PR trigger integration
│       └── config.ex          # MODIFY: Added pr_strategy config
└── test/
    ├── pr_test.exs            # EXISTING: Already implemented in prior story
    └── pr_trigger_test.exs   # NEW: PR trigger tests

# Also modified:
lib/babysitter/broadcast.ex          # ADDED: workflow_completed event
lib/babysitter/workflow_instance.ex  # MODIFY: Integrate PRTrigger on workflow completion
```

### Implementation Approach

The PR module provides PR creation capabilities:
- `Babysitter.PR.create/1` - Creates a PR with title, body, labels, reviewers
- `Babysitter.PRTrigger` - Trigger-based PR creation similar to CommitTrigger
- Configuration-driven label and reviewer assignment
- Template support for title/body based on workflow context

### Usage

Configure PR creation in ~/.config/babysitter/config.yaml:

```yaml
git:
  pr_strategy:
    trigger: workflow_complete  # or stage_complete, manual
    title_template: "{{issue.id}}: {{issue.title}}"
    body_template: |
      ## Summary
      {{stage.summary}}
    labels:
      - automated
    reviewers: []
    base: main
    draft: false
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 2.4]
- [Source: _bmad-output/planning-artifacts/architecture.md#FR-6]

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-27T17:30:00Z | initialized | Story created with td epic td-3b16e3 |
| 2026-02-27T18:50:00Z | task-complete | td-e31891: Implemented PR module, PRTrigger, and config |
| 2026-02-27T19:30:00Z | reviewed | Epic-level review completed - issues found |
| 2026-02-27T19:35:00Z | closed | Fixes applied and story approved |

## Dev Agent Record

### Completion Notes

**What was implemented:**
- Created `Babysitter.PRTrigger` module for workflow-integrated PR creation
- Extended `Babysitter.Config` with PR strategy configuration (title_template, body_template, labels, reviewers, base, draft)
- Added helper functions: git_pr_strategy/0, git_pr_trigger/0, git_pr_title_template/0, git_pr_body_template/0, git_pr_labels/0, git_pr_reviewers/0, git_pr_base/0, git_pr_draft?/0

**Key decisions:**
- Followed existing CommitTrigger pattern for consistency
- Used TemplateInterpolator for template rendering
- Support for dry-run preview before actual PR creation
- Integration with existing PR module for gh CLI operations

**Tests added:**
- Created test/pr_trigger_test.exs with 7 tests
- All 32 PR-related tests pass
- No regressions in existing tests

---

## Senior Developer Review (AI)

**Date:** 2026-02-27
**Outcome:** approved
**Action Items:** 0

### Summary

Reviewed Story 2.4 implementation for PR creation functionality. Found 1 critical issue (missing workflow integration), 2 medium issues (documentation error, weak tests), and 2 low issues (compiler warnings, error handling).

### Issues Found & Fixed

1. **[CRITICAL]** AC1 Not Fully Implemented - Added workflow integration in `workflow_instance.ex` to trigger PR creation on workflow completion
2. **[MEDIUM]** Documentation Error - Fixed file list to reflect actual changes
3. **[MEDIUM]** Weak Test Coverage - Added meaningful assertions and additional test cases
4. **[LOW]** Compiler Warnings - Fixed underscore variable usage in pr_trigger.ex
5. **[LOW]** Silent Error Swallowing - Added proper error handling for labels/reviewers

### Verification

- All 11 PR trigger tests pass
- All 39 PR-related tests pass
- No regressions in existing tests
- Code compiles without errors
