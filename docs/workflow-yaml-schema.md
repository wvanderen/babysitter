# Workflow YAML Schema

This document defines the schema for babysitter workflow configuration files.

Workflows are defined in `.babysitter/workflows/*.yaml` files.

## Top-Level Schema

```yaml
id: string                    # Unique workflow identifier (required)
name: string                  # Human-readable workflow name (required)
description: string           # Workflow description (optional)
intelligence: dumb | smart | hybrid  # Default intelligence level (optional, default: hybrid)
entry_point: string           # ID of the first stage to execute (optional, defaults to first stage)

stages: Stage[]               # Array of stage definitions (required)
transitions: Transition[]     # Explicit transition definitions (optional, can use on_success/on_failure instead)
```

### Intelligence Levels

| Level | Description |
|-------|-------------|
| `dumb` | Rules-based only, no LLM calls for intervention |
| `smart` | LLM analyzes output and makes decisions |
| `hybrid` | Dumb for happy path, smart on failure (default) |

## Stage Schema

Each stage in the `stages` array follows this schema:

```yaml
- id: string                  # Unique stage identifier (required)
  type: string                # Stage type (required)
  timeout: duration           # Maximum execution time (optional)
  on_success: string          # Stage ID to transition to on success (optional)
  on_failure: string          # Stage ID to transition to on failure (optional)
  on_timeout: string          # Stage ID to transition to on timeout (optional)
  max_retries: int            # Maximum retry attempts (optional, default: 0)
```

### Stage Types

| Type | Description | Additional Fields |
|------|-------------|-------------------|
| `agent` | Run AI agent with prompt | `agent`, `prompt` or `prompt_template` |
| `action` | Execute system action | `action`, `message`, `command` |
| `validation` | Run validation checks | `validation` |
| `decision` | LLM-powered decision point | `prompt`, `branches` |
| `parallel` | Run multiple stages concurrently | `parallel_stages` |

## Stage Type Details

### Agent Stage

Runs an AI agent with a prompt.

```yaml
- id: implementation
  type: agent
  agent: claude | opencode | cursor | custom  # Agent to use (required)
  prompt: string                    # Direct prompt text (use this OR prompt_template)
  prompt_template: string           # Template with variable interpolation
  timeout: 30m                      # Execution timeout
  validation:                       # Validations to run after stage
    - type: compile
    - type: tests
    - type: command
      command: "npm run lint"
  on_success: review
  on_failure: retry
  max_retries: 2
```

#### Template Variables

Available in `prompt_template`:

| Variable | Description |
|----------|-------------|
| `{{issue.id}}` | td issue ID |
| `{{issue.title}}` | td issue title |
| `{{issue.description}}` | td issue description |
| `{{issue.status}}` | td issue status |
| `{{issue.last_handoff.done}}` | Items marked done in last handoff |
| `{{issue.last_handoff.remaining}}` | Remaining work from last handoff |
| `{{issue.last_handoff.uncertain}}` | Uncertain items from last handoff |
| `{{context.<stage_id>_findings}}` | Output from a previous stage |

### Action Stage

Executes a system action.

```yaml
- id: complete
  type: action
  action: td_review | td_handoff | shell | restart_stage
  message: "Implementation complete, ready for human review"  # For td actions
  command: "echo 'Done'"               # For shell action
  stage: implementation                # For restart_stage action
  with_context: true                   # Pass context to restarted stage
```

#### Action Types

| Action | Description |
|--------|-------------|
| `td_review` | Submit issue for td review |
| `td_handoff` | Create td handoff with current state |
| `shell` | Execute shell command |
| `restart_stage` | Restart a specific stage |

### Validation Stage

Runs validation checks.

```yaml
- id: validate
  type: validation
  validation:
    - type: compile
    - type: tests
    - type: lint
    - type: command
      command: "npm run typecheck"
    - type: output_contains
      pattern: "BUILD SUCCESSFUL"
    - type: output_matches
      regex: "All \\d+ tests passed"
    - type: exit_code
      expected: 0
    - type: file_exists
      path: "/tmp/babysitter-demo/data.json"
    - type: file_contains
      path: "/tmp/babysitter-demo/data.json"
      pattern: "slideshow"
  on_success: complete
  on_failure: fix
```

#### Validation Types

| Type | Description | Additional Fields |
|------|-------------|-------------------|
| `compile` | Check compilation succeeds | None |
| `tests` | Run test suite | None |
| `lint` | Run linter | None |
| `command` | Execute custom command | `command` |
| `output_contains` | Check output contains pattern | `pattern` |
| `output_matches` | Check output matches regex | `regex` |
| `exit_code` | Check command exit code | `expected` |
| `file_exists` | Check file exists | `path` |
| `file_contains` | Check file contains pattern | `path`, `pattern` |

### Decision Stage

LLM-powered branching.

```yaml
- id: decide
  type: decision
  prompt: "Analyze the output and decide next action"
  branches:
    - condition: "tests pass and no errors"
      target: complete
    - condition: "minor errors found"
      target: fix
    - condition: "major issues detected"
      target: escalate
  default: escalate
```

### Parallel Stage

Run multiple stages concurrently.

```yaml
- id: parallel_checks
  type: parallel
  parallel_stages:
    - id: lint_check
      type: validation
      validation:
        - type: lint
    - id: type_check
      type: validation
      validation:
        - type: command
          command: "npm run typecheck"
  on_success: implementation
  on_failure: escalate
```

## Transitions

Transitions define how stages connect. Two formats are supported:

### Inline Transitions (Recommended)

Define transitions directly on stages using `on_success`, `on_failure`, `on_timeout`:

```yaml
stages:
  - id: start
    on_success: middle
  - id: middle
    on_success: end
    on_failure: retry
```

### Explicit Transitions

Define a separate `transitions` section:

```yaml
stages:
  - id: planning
  - id: implementation
  - id: review
  - id: complete
  - id: retry

transitions:
  - from: planning
    to: implementation
  - from: implementation
    to: review
    condition: success
  - from: implementation
    to: retry
    condition: failure
  - from: review
    to: complete
    condition: success
  - from: retry
    to: implementation
```

## Duration Format

Timeouts and durations can be specified as:

| Format | Example | Meaning |
|--------|---------|---------|
| Milliseconds | `30000` | 30 seconds |
| Seconds | `30s` | 30 seconds |
| Minutes | `5m` | 5 minutes |
| Hours | `1h` | 1 hour |
| Infinite | `infinity` | No timeout |

## Example Workflows

The `.babysitter/workflows/` directory contains ready-to-use example workflows:

### default.yaml

A comprehensive workflow demonstrating all schema features:

```yaml
id: default
name: Default Development Workflow
intelligence: hybrid

variables:
  project_root: .
  test_timeout: 5m

stages:
  - id: analyze
    type: agent
    agent: claude
    prompt: Analyze the codebase and understand the task requirements
    timeout: 10m
    on_success: implement

  - id: implement
    type: agent
    agent: claude
    prompt: Implement the required changes with tests
    timeout: 30m
    validation:
      - type: compile
      - type: tests
    on_success: review
    on_failure: fix
    max_retries: 2

  - id: fix
    type: decision
    prompt: Analyze failures and determine fix strategy
    on_success: implement

  - id: review
    type: agent
    agent: claude
    prompt: Review implementation for quality and completeness
    timeout: 10m
    on_success: complete

  - id: complete
    type: action
    action: td_review
    message: Implementation complete
```

### bugfix.yaml

A workflow optimized for bug fixes with reproduction and verification:

```yaml
id: bugfix
name: Bug Fix Workflow
intelligence: smart

stages:
  - id: triage
    type: agent
    agent: claude
    prompt: Analyze the bug report and identify root cause
    timeout: 15m
    on_success: reproduce

  - id: reproduce
    type: agent
    agent: claude
    prompt: Create a test case that reproduces the bug
    timeout: 10m
    validation:
      - type: tests
    on_success: fix
    on_failure: triage

  - id: fix
    type: agent
    agent: claude
    prompt: Fix the bug ensuring the reproduction test passes
    timeout: 20m
    validation:
      - type: compile
      - type: tests
    on_success: verify
    on_failure: triage
    max_retries: 2

  - id: verify
    type: validation
    validation:
      - type: tests
    on_success: complete
    on_failure: fix

  - id: complete
    type: action
    action: td_review
    message: Bug fix complete and verified
```

### feature.yaml

A workflow for feature development with planning and integration:

```yaml
id: feature
name: Feature Development Workflow
intelligence: hybrid

stages:
  - id: plan
    type: agent
    agent: claude
    prompt: Plan the feature implementation with acceptance criteria
    timeout: 15m
    on_success: implement

  - id: implement
    type: agent
    agent: claude
    prompt: Implement the feature with comprehensive tests
    timeout: 45m
    validation:
      - type: compile
      - type: tests
    on_success: integrate
    on_failure: debug
    max_retries: 3

  - id: debug
    type: decision
    prompt: Analyze issues and determine resolution
    on_success: implement

  - id: integrate
    type: agent
    agent: claude
    prompt: Ensure feature integrates well with existing code
    timeout: 15m
    validation:
      - type: tests
    on_success: review

  - id: review
    type: agent
    agent: claude
    prompt: Review for code quality, edge cases, and documentation
    timeout: 10m
    on_success: complete

  - id: complete
    type: action
    action: td_review
    message: Feature implementation complete
```

## Complete Example

```yaml
id: feature-development
name: Feature Development
description: Standard workflow for implementing new features
intelligence: hybrid
entry_point: planning

stages:
  - id: planning
    type: action
    action: td_query
    td_query: "status = open AND type = feature AND priority <= P1"
    max_issues: 1
    on_success: implementation

  - id: implementation
    type: agent
    agent: claude
    prompt_template: |
      Implement the feature described in td issue {{issue.id}}.
      Title: {{issue.title}}
      Context from handoff: {{issue.last_handoff.remaining}}
    timeout: 30m
    validation:
      - type: compile
      - type: tests
      - type: command
        command: "npm run lint"
    on_success: review
    on_failure: retry
    max_retries: 2

  - id: review
    type: agent
    agent: claude
    prompt: |
      Review your implementation of {{issue.id}}.
      Check for edge cases, error handling, and code quality.
    timeout: 10m
    on_success: complete
    on_failure: fix

  - id: fix
    type: agent
    agent: claude
    prompt_template: |
      Fix the issues found in review.
      Issues: {{context.review_issues}}
    timeout: 15m
    on_success: review
    max_retries: 3

  - id: retry
    type: action
    action: restart_stage
    stage: implementation
    with_context: true
    on_success: implementation

  - id: complete
    type: action
    action: td_review
    message: "Implementation complete, ready for human review"
```

## JSON Schema

For validation tools, the equivalent JSON Schema:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["id", "stages"],
  "properties": {
    "id": { "type": "string" },
    "name": { "type": "string" },
    "description": { "type": "string" },
    "intelligence": {
      "type": "string",
      "enum": ["dumb", "smart", "hybrid"],
      "default": "hybrid"
    },
    "entry_point": { "type": "string" },
    "stages": {
      "type": "array",
      "items": { "$ref": "#/definitions/stage" },
      "minItems": 1
    },
    "transitions": {
      "type": "array",
      "items": { "$ref": "#/definitions/transition" }
    }
  },
  "definitions": {
    "stage": {
      "type": "object",
      "required": ["id", "type"],
      "properties": {
        "id": { "type": "string" },
        "type": {
          "type": "string",
          "enum": ["agent", "action", "validation", "decision", "parallel"]
        },
        "timeout": { "type": ["string", "integer"] },
        "on_success": { "type": "string" },
        "on_failure": { "type": "string" },
        "on_timeout": { "type": "string" },
        "max_retries": { "type": "integer", "minimum": 0 }
      }
    },
    "transition": {
      "type": "object",
      "required": ["from", "to"],
      "properties": {
        "from": { "type": "string" },
        "to": { "type": "string" },
        "condition": { "type": "string" }
      }
    }
  }
}
```
