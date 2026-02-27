# Babysitter Workflow Guide

A practical guide to creating and using workflows in Babysitter.

## Quick Start

### Your First Workflow

Create a file at `.babysitter/workflows/my-first.yaml`:

```yaml
id: my-first
name: My First Workflow
stages:
  - id: hello
    type: action
    command: echo "Hello, Babysitter!"
    on_success: done
  - id: done
    type: action
    command: echo "Workflow complete!"
```

That's it! You have a working workflow with two stages.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Workflow** | A YAML file defining a sequence of stages |
| **Stage** | A single step: action, agent, decision, or validation |
| **Transition** | How control flows between stages |
| **Validation** | Checks that run after a stage completes |

## Schema Reference

### Required Fields

Every workflow MUST have:

```yaml
id: unique-identifier    # lowercase, numbers, underscores, hyphens
name: Human Readable Name
stages: []               # at least one stage
```

### Optional Top-Level Fields

```yaml
description: "What this workflow does"
intelligence: hybrid     # dumb | smart | hybrid (default: hybrid)
entry_point: first_stage # defaults to first stage in list
variables:               # reusable values
  project_root: .
  timeout: 5m
```

### Intelligence Levels

| Level | Behavior | Use Case |
|-------|----------|----------|
| `dumb` | Rules only, no LLM | Simple scripts, CI/CD |
| `smart` | LLM makes all decisions | Complex decision-making |
| `hybrid` | Rules for success, LLM for failure | Most development workflows |

### Stage Types

#### Action Stage

Execute shell commands:

```yaml
- id: build
  type: action
  command: npm run build
  timeout: 5m
  on_success: test
  on_failure: fail
```

#### Agent Stage

Run an AI agent with a prompt:

```yaml
- id: implement
  type: agent
  prompt: |
    Implement the feature described in the issue.
    Follow existing code patterns.
  timeout: 30m
  validation:
    - type: compile
    - type: tests
  on_success: review
  on_failure: retry
  max_retries: 2
```

#### Decision Stage

LLM-powered branching:

```yaml
- id: decide_next
  type: decision
  on_success: continue
```

### Validation Types

| Type | Description | Required Fields |
|------|-------------|-----------------|
| `compile` | Check code compiles | none |
| `tests` | Run test suite | none |
| `output_contains` | Check output for pattern | `pattern` |
| `file_exists` | Verify file exists | `path` |
| `file_contains` | Check file for pattern | `path`, `pattern` |

Example:

```yaml
validation:
  - type: compile
  - type: tests
  - type: output_contains
    pattern: "BUILD SUCCESS"
  - type: file_exists
    path: dist/bundle.js
```

### Transitions

Two ways to define stage flow:

**Inline (recommended):**
```yaml
stages:
  - id: a
    on_success: b
    on_failure: fail
  - id: b
    on_success: c
```

**Explicit:**
```yaml
stages:
  - id: a
  - id: b
  - id: c

transitions:
  - from: a
    to: b
    condition: success
  - from: b
    to: c
    condition: success
```

### Variables

Define reusable values:

```yaml
variables:
  project_root: .
  test_timeout: 5m
  build_cmd: npm run build

stages:
  - id: test
    type: action
    command: cd {{project_root}} && npm test
    timeout: "{{test_timeout}}"
```

## Example Workflows

### Minimal Workflow

```yaml
id: minimal
name: Minimal Example
stages:
  - id: run
    type: action
    command: echo "Done!"
```

### Development Workflow

```yaml
id: dev
name: Development
intelligence: hybrid

stages:
  - id: setup
    type: action
    command: npm install
    timeout: 2m
    on_success: implement

  - id: implement
    type: agent
    prompt: Implement the assigned task with tests
    timeout: 30m
    validation:
      - type: compile
      - type: tests
    on_success: complete
    on_failure: fix

  - id: fix
    type: decision
    on_success: implement

  - id: complete
    type: action
    command: echo "Task complete!"
```

### CI/CD Workflow

```yaml
id: cicd
name: CI/CD Pipeline
intelligence: dumb

variables:
  node_version: "20"

stages:
  - id: install
    type: action
    command: npm ci
    timeout: 3m
    on_success: lint

  - id: lint
    type: action
    command: npm run lint
    timeout: 2m
    on_success: test

  - id: test
    type: action
    command: npm test -- --coverage
    timeout: 5m
    validation:
      - type: output_contains
        pattern: "All tests passed"
    on_success: build

  - id: build
    type: action
    command: npm run build
    timeout: 5m
    validation:
      - type: file_exists
        path: dist/index.js
    on_success: complete

  - id: complete
    type: action
    command: echo "Pipeline successful!"
```

## Troubleshooting

### Common Errors

#### "Missing required field: id"

**Cause:** Workflow file missing the `id` field.

**Fix:**
```yaml
id: my-workflow  # Add this line
name: My Workflow
stages: []
```

#### "Missing required field: name"

**Cause:** Workflow file missing the `name` field.

**Fix:**
```yaml
id: my-workflow
name: My Workflow  # Add this line
stages: []
```

#### "Missing required field: stages"

**Cause:** No stages defined in workflow.

**Fix:**
```yaml
id: my-workflow
name: My Workflow
stages:           # Add at least one stage
  - id: run
    type: action
    command: echo "Hello"
```

#### "Stage missing required field: id"

**Cause:** A stage is missing its `id` field.

**Fix:**
```yaml
stages:
  - id: my-stage  # Add this line
    type: action
    command: echo "Hello"
```

#### "Stage missing required field: type"

**Cause:** A stage is missing its `type` field.

**Fix:**
```yaml
stages:
  - id: my-stage
    type: action  # Add: action, agent, or decision
    command: echo "Hello"
```

#### "Invalid stage type: 'foo'"

**Cause:** Stage type is not one of the allowed values.

**Allowed types:** `action`, `agent`, `decision`

**Fix:**
```yaml
stages:
  - id: my-stage
    type: action  # Use: action, agent, or decision
```

#### "Invalid intelligence level: 'medium'"

**Cause:** Intelligence value is not recognized.

**Allowed values:** `dumb`, `smart`, `hybrid`

**Fix:**
```yaml
intelligence: hybrid  # Use: dumb, smart, or hybrid
```

#### "Invalid timeout format"

**Cause:** Timeout is not in a recognized format.

**Allowed formats:** `30s`, `5m`, `1h`, or number (seconds)

**Fix:**
```yaml
timeout: 5m    # Valid: 30s, 5m, 1h
# or
timeout: 300   # Seconds as number
```

#### "Transition references undefined stage"

**Cause:** A transition references a stage ID that doesn't exist.

**Fix:** Ensure all stage IDs in transitions exist in the `stages` array.

```yaml
stages:
  - id: start
    on_success: end    # 'end' must exist
  - id: end            # Add this stage
    type: action
    command: echo "Done"
```

#### "Validation missing required field: pattern"

**Cause:** `output_contains` or `file_contains` validation missing pattern.

**Fix:**
```yaml
validation:
  - type: output_contains
    pattern: "expected output"  # Add this line
```

#### "Validation missing required field: path"

**Cause:** `file_exists` or `file_contains` validation missing path.

**Fix:**
```yaml
validation:
  - type: file_exists
    path: "path/to/file.txt"  # Add this line
```

#### "Duplicate stage ID"

**Cause:** Two stages have the same `id`.

**Fix:** Use unique IDs for each stage.

```yaml
stages:
  - id: step1    # Unique
    type: action
  - id: step2    # Also unique
    type: action
```

#### "Invalid stage ID format"

**Cause:** Stage ID contains invalid characters.

**Allowed:** lowercase letters, numbers, underscores

**Fix:**
```yaml
- id: my_stage_1    # Valid
# - id: My-Stage     # Invalid: uppercase, hyphen
# - id: my stage     # Invalid: space
```

#### "Invalid workflow ID format"

**Cause:** Workflow ID contains invalid characters.

**Allowed:** lowercase letters, numbers, underscores, hyphens

**Fix:**
```yaml
id: my-workflow_1   # Valid
# id: My Workflow   # Invalid: uppercase, space
```

### Validation Errors

#### Compile validation fails

**Symptoms:** Stage fails on compile check.

**Debug:**
1. Run compile command manually
2. Check for syntax errors in code
3. Verify dependencies are installed

#### Tests validation fails

**Symptoms:** Stage fails on test check.

**Debug:**
1. Run tests locally: `npm test` or equivalent
2. Check for failing tests
3. Review test output for errors

#### Output pattern not found

**Symptoms:** `output_contains` validation fails.

**Debug:**
1. Run command manually to see actual output
2. Check pattern is correct (case-sensitive)
3. Verify pattern doesn't have extra whitespace

### Workflow Execution Issues

#### Workflow hangs or times out

**Cause:** Command or agent taking too long.

**Fix:**
1. Increase timeout value
2. Break into smaller stages
3. Check for infinite loops in commands

#### Stage not executing

**Cause:** No transition path to the stage.

**Fix:** Ensure `on_success` or `on_failure` references the stage, or add a transition.

#### Variables not interpolating

**Symptoms:** `{{variable}}` appears literally in output.

**Debug:**
1. Check variable is defined in `variables` section
2. Verify correct syntax: `{{variable}}` (double braces)
3. Variable names are case-sensitive

### Getting Help

1. **Check schema:** Validate against `.babysitter/schemas/workflow.schema.json`
2. **Review examples:** See `.babysitter/workflows/` for working examples
3. **Enable debug mode:** Set `intelligence: smart` for more verbose output
4. **Simplify:** Create minimal reproduction of the issue

## Best Practices

1. **Start simple:** Begin with action stages, add complexity as needed
2. **Use meaningful IDs:** `run_tests` not `stage_1`
3. **Set timeouts:** Prevent hung workflows
4. **Add validation:** Catch issues early
5. **Handle failures:** Always define `on_failure` paths
6. **Document variables:** Comment what each variable is for
7. **Test incrementally:** Add one stage at a time

## See Also

- [Workflow YAML Schema](./workflow-yaml-schema.md) - Complete schema reference
- [JSON Schema](../.babysitter/schemas/workflow.schema.json) - For validation tools
- [Example Workflows](../.babysitter/workflows/) - Working examples
