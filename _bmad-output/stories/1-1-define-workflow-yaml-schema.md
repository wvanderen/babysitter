# Story 1.1: Define Workflow YAML Schema

Status: ready-for-dev

<!-- BMAD-TD Integration: This story is synced with td epic td-0176be -->

## td Integration

- **td Epic**: `td-0176be`
- **td Tasks**: 4 issues (4 open, 0 in-progress, 0 blocked)
- **Last Sync**: 2026-02-27
- **Sync Status**: initialized

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1 | `td-ea10aa` | open |
| Task 2 | `td-8fe0ae` | open |
| Task 3 | `td-0d89bf` | open |
| Task 4 | `td-f72b73` | open |

---

## Story

As a user,
I want a clear YAML schema for defining workflows,
so that I know the correct structure for stages, transitions, and configuration.

## Acceptance Criteria

1. **Given** the documentation for workflow YAML format
   **When** I create a workflow file
   **Then** I can define: id, name, stages[], transitions, intelligence level

2. **Given** the documentation for workflow YAML format
   **When** I create a workflow file
   **Then** each stage can have: id, type, agent, prompt, timeout, validation[], on_success, on_failure

3. **Given** an invalid workflow YAML file
   **When** I try to use it
   **Then** I receive a clear error message indicating what's wrong

## Tasks / Subtasks

- [ ] Task 1: Create workflow schema documentation (AC: #1, #2) [td:td-ea10aa]
  - [ ] Document top-level fields: id, name, stages[], transitions, intelligence
  - [ ] Document stage fields: id, type, agent, prompt, timeout, validation[], on_success, on_failure
  - [ ] Document transition syntax and stage references
  - [ ] Add examples for common workflow patterns (default, bugfix, feature)

- [ ] Task 2: Create JSON Schema for YAML validation (AC: #3) [td:td-8fe0ae]
  - [ ] Define JSON Schema for workflow structure
  - [ ] Include all required and optional fields
  - [ ] Add field descriptions and constraints
  - [ ] Save to `.babysitter/schemas/workflow.schema.json`

- [x] Task 3: Add example workflow files (AC: #1) [td:td-0d89bf]
  - [x] Create `.babysitter/workflows/default.yaml` with full example
  - [x] Create `.babysitter/workflows/bugfix.yaml` example
  - [x] Create `.babysitter/workflows/feature.yaml` example
  - [x] Ensure examples demonstrate all schema features

- [ ] Task 4: Add documentation to docs/ (AC: #1, #2, #3) [td:td-f72b73]
  - [ ] Create `docs/workflow-guide.md` with schema reference
  - [ ] Include troubleshooting section for common errors
  - [ ] Add quick-start examples

## Dev Notes

### Architecture Context

From `architecture.md`:
- Workflows are defined in YAML format in `.babysitter/workflows/`
- Parsed by `elixir/lib/babysitter/workflow/parser.ex`
- Validated by `elixir/lib/babysitter/workflow/validator.ex`
- Intelligence levels: dumb/smart/hybrid

### Schema Requirements

Based on PRD and architecture:

**Top-level fields:**
```yaml
id: string          # Unique workflow identifier
name: string        # Human-readable name
description: string # Optional description
intelligence: enum  # dumb | smart | hybrid
stages: []          # List of stage definitions
transitions: []     # Stage transition rules
```

**Stage fields:**
```yaml
id: string          # Unique stage identifier
type: enum          # agent | validation | intervention | human
agent: string       # Agent type (claude, opencode, cursor)
prompt: string      # Prompt template or file reference
timeout: number     # Timeout in seconds (optional)
validation: []      # Validation commands (optional)
on_success: string  # Next stage on success
on_failure: string  # Next stage or intervention on failure
```

**Transition syntax:**
```yaml
transitions:
  - from: stage_id
    to: next_stage_id
    condition: success | failure | timeout
```

### Project Structure Notes

- Schema file: `.babysitter/schemas/workflow.schema.json`
- Example workflows: `.babysitter/workflows/*.yaml`
- Documentation: `docs/workflow-guide.md`

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Workflow definition]
- [Source: docs/prd-babysitter-2026-02-13.md#FR-1]
- [Source: _bmad-output/project-context.md#Development Workflow]

## Dev Agent Record

### Agent Model Used

Claude (glm-5)

### Debug Log References

N/A

### Completion Notes List

**Task 3: Add example workflow files**
- Created `default.yaml` - Comprehensive workflow demonstrating all schema features including variables, all stage types (action, agent, decision), validation types (output_contains, file_exists, file_contains, compile, tests), timeouts, max_retries, on_success/on_failure handlers, and transitions
- Created `bugfix.yaml` - Bug fix workflow with triage, reproduce, diagnose, fix, and verify stages demonstrating smart intelligence level and error handling
- Created `feature.yaml` - Feature development workflow from kickoff to PR preparation demonstrating hybrid intelligence, integration testing, and code review stages

### File List

- `.babysitter/workflows/default.yaml` (new)
- `.babysitter/workflows/bugfix.yaml` (new)
- `.babysitter/workflows/feature.yaml` (new)

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-27 | initialized | Story created with td epic td-0176be |
| 2026-02-27T12:32 | task-complete | td-0d89bf: Add example workflow files |
