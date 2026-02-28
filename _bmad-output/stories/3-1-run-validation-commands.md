# Story 3.1: Run Validation Commands

Status: ready-for-dev

<!-- BMAD-TD Integration: This story is synced with td epic td-454b8e -->

## td Integration

- **td Epic**: `td-454b8e`
- **td Tasks**: 4 issues (2 open, 0 in-progress, 0 blocked, 2 in_review)
- **Last Sync**: 2026-02-28T12:30:00
- **Sync Status**: initialized

### Task → td Mapping

| Task | td Issue | Status |
|------|----------|--------|
| Task 1 | `td-f31e80` | in_review |
| Task 2 | `td-51d1fb` | in_review |
| Task 3 | `td-da3ef9` | open |
| Task 4 | `td-35c831` | open |

---

## Story

As a user,
I want validation commands to run after stages,
so that quality gates can block progression on failure.

## Acceptance Criteria

1. **Given** a stage with validation configured **When** the stage completes **Then** compile validation runs `mix compile` / `go build` / `npm run build`
2. **And** test validation runs `mix test` / `go test` / `pytest`
3. **And** custom commands execute with exit code determining pass/fail
4. **And** validation failures block progression and trigger intervention engine

## Tasks / Subtasks

- [x] Task 1: Implement validation infrastructure in Elixir workflow engine (AC: #1, #2, #3) [td:td-f31e80]
  - [x] 1.1 Create Validator module in elixir/lib/babysitter/workflow/
  - [x] 1.2 Define validation command config schema
  - [x] 1.3 Implement compile validation runner
  - [x] 1.4 Implement test validation runner
  - [x] 1.5 Implement custom command runner
- [x] Task 2: Add language-specific detection and command mapping (AC: #1, #2, #3) [td:td-51d1fb]
  - [x] 2.1 Detect project type from mix.exs/go.mod/package.json
  - [x] 2.2 Map project type to validation commands
  - [x] 2.3 Handle mixed monorepo scenarios
- [ ] Task 3: Integrate validation with workflow stage execution (AC: #4) [td:td-da3ef9]
  - [ ] 3.1 Call validator after stage completion
  - [ ] 3.2 Block progression on validation failure
  - [ ] 3.3 Trigger intervention engine on failure
- [x] Task 4: Add validation node to LangGraph workflow graph (AC: #1-4) [td:td-35c831]
  - [x] 4.1 Create validate.py node
  - [x] 4.2 Implement validation node that calls Elixir validator API
  - [x] 4.3 Handle validation response and state transitions

## Dev Notes

### Architecture Context

- **FR-7**: Validation stages execute compile checks, test runs, lint, and custom command validations
- Validation runs after stage completion in the workflow execution cycle
- Failed validations should block progression and trigger the intervention engine

### Key Files

| File | Purpose |
|------|---------|
| `elixir/lib/babysitter/workflow/validator.ex` | Elixir validation runner |
| `langgraph/src/babysitter_agent/nodes/validate.py` | LangGraph validation node |

### Validation Types (from workflow schema)

1. `output_contains` - Check stage output for expected patterns
2. `file_exists` - Verify files were created
3. `file_contains` - Check file contents
4. `compile` - Run language-specific compile commands
5. `tests` - Run language-specific test commands

### Language Detection

- Elixir: `mix.exs` → `mix compile`, `mix test`
- Go: `go.mod` → `go build ./...`, `go test ./...`
- Node: `package.json` → `npm run build`, `npm test`

### Integration Points

- Elixir StageExecutor calls Validator after stage completes
- Validation results stored in session state
- Failed validations trigger intervention engine (dumb → smart → human)
- LangGraph validate.py node calls Elixir API for validation execution

### Testing Standards

- Unit tests for each validation type
- Test project type detection logic
- Integration tests for validation → intervention flow
- Mock validation commands for predictable testing

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#FR-7]
- [Source: _bmad-output/planning-artifacts/epics.md#Story-3.1]
- [Source: _bmad-output/planning-artifacts/architecture.md#Requirements-to-Structure-Mapping]

## Dev Agent Record

### Agent Model Used

Claude (glm-5)

### Debug Log References

N/A - All tests passed on first run after implementation

### Completion Notes List

**Task 4: Add validation node to LangGraph workflow graph**

- Created `langgraph/src/babysitter_agent/nodes/` directory structure
- Implemented `validate.py` node with:
  - `ValidationConfig` dataclass for validation configuration
  - `ValidationResult` dataclass for validation results
  - `validate_node()` function that processes pending validations
  - `determine_validation_action()` conditional edge for routing
  - `_call_elixir_validation_api()` to call Elixir validation endpoint
- Updated `state.py` to include validation-related fields:
  - `pending_validations`: list of validation configs to run
  - `validation_results`: accumulated validation results
  - `elixir_api_base_url`: base URL for Elixir API
- Updated `graph.py` to integrate validation node into workflow:
  - Added "validate" node to graph
  - Added conditional edges for validation routing
  - Routes to "intervene" on validation failure
- Added `httpx>=0.27.0` to dependencies
- Created comprehensive unit tests (11 tests) for validation node

### File List

| File | Action | Description |
|------|--------|-------------|
| `langgraph/src/babysitter_agent/nodes/__init__.py` | NEW | Node package init with exports |
| `langgraph/src/babysitter_agent/nodes/validate.py` | NEW | Validation node implementation |
| `langgraph/src/babysitter_agent/state.py` | MODIFIED | Added validation state fields |
| `langgraph/src/babysitter_agent/graph.py` | MODIFIED | Integrated validation node |
| `langgraph/pyproject.toml` | MODIFIED | Added httpx dependency |
| `langgraph/tests/test_nodes/__init__.py` | NEW | Test package init |
| `langgraph/tests/test_nodes/test_validate.py` | NEW | Validation node tests (11 tests) |
| `langgraph/tests/test_graph.py` | MODIFIED | Updated for new graph structure |

---

## td Sync Log

| Timestamp | Action | Details |
|-----------|--------|---------|
| 2026-02-28T12:30:00 | initialized | Story created with td epic td-454b8e |
| 2026-02-28T12:30:00 | task-in_review | td-f31e80: Task 1 already in review |
| 2026-02-28T12:30:00 | task-in_review | td-51d1fb: Task 2 already in review |
| 2026-02-28T13:15:00 | task-complete | td-35c831: Task 4 - Add validation node to LangGraph workflow graph |
