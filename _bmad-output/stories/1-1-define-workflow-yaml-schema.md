# Story 1.1: Define Workflow YAML Schema

Status: ready-for-dev

<!-- BMAD-TD Integration: This story is synced with td epic td-0176be -->

## td Integration

- **td Epic**: `td-0176be`
- **td Tasks**: 4 issues (0 open, 0 in-progress, 0 blocked, 4 completed/in_review)
- **Last Sync**: 2026-02-27
- **Sync Status**: active

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1 | `td-ea10aa` | in_review |
| Task 2 | `td-8fe0ae` | in_review |
| Task 3 | `td-0d89bf` | in_review |
| Task 4 | `td-f72b73` | in_review |

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

- [x] Task 1: Create workflow schema documentation (AC: #1, #2) [td:td-ea10aa]
  - [x] Document top-level fields: id, name, stages[], transitions, intelligence
  - [x] Document stage fields: id, type, agent, prompt, timeout, validation[], on_success, on_failure
  - [x] Document transition syntax and stage references
  - [x] Add examples for common workflow patterns (default, bugfix, feature)

- [x] Task 2: Create JSON Schema for YAML validation (AC: #3) [td:td-8fe0ae]
  - [x] Define JSON Schema for workflow structure
  - [x] Include all required and optional fields
  - [x] Add field descriptions and constraints
  - [x] Save to `.babysitter/schemas/workflow.schema.json`

- [x] Task 3: Add example workflow files (AC: #1) [td:td-0d89bf]
  - [x] Create `.babysitter/workflows/default.yaml` with full example
  - [x] Create `.babysitter/workflows/bugfix.yaml` example
  - [x] Create `.babysitter/workflows/feature.yaml` example
  - [x] Ensure examples demonstrate all schema features

- [x] Task 4: Add documentation to docs/ (AC: #1, #2, #3) [td:td-f72b73]
  - [x] Create `docs/workflow-guide.md` with schema reference
  - [x] Include troubleshooting section for common errors
  - [x] Add quick-start examples

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

**Task 1: Create workflow schema documentation**
- Enhanced `docs/workflow-yaml-schema.md` with "Example Workflows" section
- Added complete examples for default.yaml, bugfix.yaml, and feature.yaml patterns
- Examples demonstrate all schema features: stages, transitions, validation, intelligence levels
- Links workflow examples to actual files in `.babysitter/workflows/`

**Task 3: Add example workflow files**
- Created `default.yaml` - Comprehensive workflow demonstrating all schema features including variables, all stage types (action, agent, decision), validation types (output_contains, file_exists, file_contains, compile, tests), timeouts, max_retries, on_success/on_failure handlers, and transitions
- Created `bugfix.yaml` - Bug fix workflow with triage, reproduce, diagnose, fix, and verify stages demonstrating smart intelligence level and error handling
- Created `feature.yaml` - Feature development workflow from kickoff to PR preparation demonstrating hybrid intelligence, integration testing, and code review stages

**Task 2: Create JSON Schema for YAML validation**
- Created `workflow.schema.json` - Complete JSON Schema (Draft-07) for workflow YAML validation
- Defines all required fields: id, name, stages
- Defines all optional fields: description, intelligence, variables, transitions, entry_point
- Stage definition supports: action, agent, decision types with appropriate fields
- Validation types: output_contains, file_exists, file_contains, compile, tests
- Transition definition with from, to, condition fields
- Includes field descriptions, constraints, examples, and conditional validation rules

**Task 4: Add documentation to docs/**
- Created `docs/workflow-guide.md` - Comprehensive user guide for workflow creation
- Quick Start section with minimal working example
- Schema reference for all required/optional fields
- Stage types reference (action, agent, decision) with examples
- Validation types reference with usage examples
- Transitions documentation (inline and explicit formats)
- Variables documentation with interpolation syntax
- Three complete example workflows (minimal, development, CI/CD)
- Troubleshooting section with 14 common errors and fixes
- Best practices and related documentation links

### File List

- `.babysitter/workflows/default.yaml` (new)
- `.babysitter/workflows/bugfix.yaml` (new)
- `.babysitter/workflows/feature.yaml` (new)
- `.babysitter/schemas/workflow.schema.json` (new)
- `docs/workflow-guide.md` (new)
- `docs/workflow-yaml-schema.md` (modified - added example workflows section)

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-27 | initialized | Story created with td epic td-0176be |
| 2026-02-27T12:32 | task-complete | td-0d89bf: Add example workflow files |
| 2026-02-27T12:40 | task-complete | td-8fe0ae: Create JSON Schema for YAML validation |
| 2026-02-27T12:55 | task-complete | td-f72b73: Add documentation to docs/ |
| 2026-02-27T14:20 | task-complete | td-ea10aa: Create workflow schema documentation |
