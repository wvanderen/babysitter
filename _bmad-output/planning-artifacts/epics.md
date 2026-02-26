---
stepsCompleted: [1, 2, 3]
inputDocuments:
  - docs/prd-babysitter-2026-02-13.md
  - docs/product-brief-agent_monitor-2026-02-03.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/research/technical-langgraph-integration-research-2026-02-24.md
---

# babysitter - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for babysitter, decomposing the requirements from the PRD, UX Design if it exists, and Architecture requirements into implementable stories.

## Requirements Inventory

### Functional Requirements

**FR-1:** Workflow definition and execution - Parse YAML workflow files with stage graphs, transitions, and intelligence levels

**FR-2:** Session lifecycle management - Spawn, monitor, and manage tmux-based AI agent sessions

**FR-3:** Output capture and parsing - Capture stdout/stderr, extract signals (completion markers, errors), detect progress

**FR-4:** Intervention engine - Handle failures via rules-based ("dumb") or LLM-powered ("smart") intervention

**FR-5:** TD integration - Read issues from td SQLite, write logs/handoffs/reviews via td CLI

**FR-6:** Git integration - Configurable commit triggers, message templates, PR creation

**FR-7:** Validation stages - Execute compile checks, test runs, lint, and custom command validations

**FR-8:** Real-time TUI updates - WebSocket streaming to Go TUI for live session display

**FR-9:** Human-in-the-loop patterns - Interrupt/resume for approvals, escalation to human

**FR-10:** State persistence and recovery - Survive daemon restarts, recover sessions from checkpoints

### NonFunctional Requirements

**NFR-1:** Fault tolerance - OTP supervision trees, crash recovery, isolated process layers

**NFR-2:** Latency - WebSocket updates < 1 second between TUI and Elixir

**NFR-3:** Uptime - 24+ hours continuous operation

**NFR-4:** State durability - Sessions survive daemon restarts via tmux + SQLite

**NFR-5:** Attachability - All sessions run in tmux for debugging/inspection

### Additional Requirements

- **Starter Template:** Custom LangGraph project structure (not template-based) - `langgraph/` folder with `src/babysitter_agent/`, `langgraph.json`
- **State Authority:** Elixir owns session state, LangGraph is stateless compute engine
- **Communication:** Elixir↔LangGraph REST + polling (2-3s interval), retry 3x with exponential backoff
- **Checkpointer:** SQLite (`data/langgraph/checkpoints.db`) for MVP
- **Error Handling:** Retry 3x with exponential backoff (1s, 2s, 4s), then escalate
- **Protocol:** Phoenix Channels (Elixir↔Go TUI), REST (Elixir↔LangGraph)
- **Deployment:** Docker Compose: Single `docker-compose.yml` for all services
- **Session Mapping:** Elixir stores `langgraph_thread_id` and `langgraph_checkpoint_id` in SQLite

## Epic List

### Epic 1: Running Workflows
Users can define and execute multi-stage workflows that sequence AI agent work across td issues, with sessions that survive daemon restarts.

**FRs covered:** FR-1, FR-2, FR-3, FR-10, NFR-4, NFR-5
**Goal:** Core orchestration engine - workflow parsing, stage execution, tmux-based session management, output capture, state persistence, LangGraph integration, and recovery

### Epic 2: Connecting Tools
Users can pull issues from td and write back handoffs, logs, and reviews, plus configure commit triggers and create PRs automatically.

**FRs covered:** FR-5, FR-6
**Goal:** Bidirectional td and git integration - read issues, write context, commit strategy, PR creation

### Epic 3: Quality Gates
Users can validate work at each stage with compile, tests, lint, and custom commands before progression.

**FRs covered:** FR-7
**Goal:** Quality gates - validation stages that gate workflow progression

### Epic 4: Monitoring & Control
Users can monitor session progress live via TUI, interact with running workflows, and get automatic recovery when things fail.

**FRs covered:** FR-4, FR-8, FR-9, NFR-1, NFR-2, NFR-3
**Goal:** Go TUI with WebSocket streaming, dumb + smart intervention, human-in-the-loop approvals, fault tolerance

### FR Coverage Map

| FR | Epic |
|----|------|
| FR-1: Workflow definition | Epic 1 - Running Workflows |
| FR-2: Session lifecycle | Epic 1 - Running Workflows |
| FR-3: Output capture | Epic 1 - Running Workflows |
| FR-4: Intervention engine | Epic 4 - Monitoring & Control |
| FR-5: TD integration | Epic 2 - Connecting Tools |
| FR-6: Git integration | Epic 2 - Connecting Tools |
| FR-7: Validation stages | Epic 3 - Quality Gates |
| FR-8: Real-time TUI | Epic 4 - Monitoring & Control |
| FR-9: Human-in-the-loop | Epic 4 - Monitoring & Control |
| FR-10: State persistence | Epic 1 - Running Workflows |

---

## Epic 1: Running Workflows

### Story 1.0: Infrastructure Setup

As a user,
I want tmux and required dependencies to be available,
So that agent sessions can run and be attachable for debugging.

**Acceptance Criteria:**

**Given** a fresh environment
**When** babysitter starts
**Then** tmux is verified available
**And** required directories are created
**And** error is clear if tmux is missing

### Story 1.1: Define Workflow YAML Schema

As a user,
I want a clear YAML schema for defining workflows,
So that I know the correct structure for stages, transitions, and configuration.

**Acceptance Criteria:**

**Given** the documentation for workflow YAML format
**When** I create a workflow file
**Then** I can define: id, name, stages[], transitions, intelligence level
**And** each stage can have: id, type, agent, prompt, timeout, validation[], on_success, on_failure

### Story 1.2: Parse Workflow YAML Files

As a user,
I want babysitter to parse YAML workflow files,
So that workflows can be loaded and executed.

**Acceptance Criteria:**

**Given** a valid YAML workflow file in `.babysitter/workflows/`
**When** babysitter parses the file
**Then** the workflow is loaded with all stages, transitions, and configuration
**And** invalid YAML returns a clear error message

### Story 1.3: Validate Workflow Configuration

As a user,
I want workflow configuration to be validated before execution,
So that errors are caught early with helpful messages.

**Acceptance Criteria:**

**Given** a parsed workflow
**When** validation runs
**Then** all stage references in transitions are verified
**And** required fields are present
**And** intelligence level is valid (dumb/smart/hybrid)

### Story 1.4: Execute Workflow Stages

As a user,
I want workflows to execute stage-by-stage following defined transitions,
So that work progresses automatically from planning to completion.

**Acceptance Criteria:**

**Given** a validated workflow
**When** execution starts
**Then** stages run in order following transition rules
**And** on_success moves to next stage
**And** on_failure triggers intervention or retry

### Story 1.5: Manage Agent Sessions

As a user,
I want AI agent sessions to run in tmux,
So that sessions survive daemon restarts and I can attach for debugging.

**Acceptance Criteria:**

**Given** a workflow with agent stage
**When** the stage executes
**Then** a tmux session is created with the agent process
**And** stdout/stderr are captured
**And** session can be attached via tmux command

### Story 1.6: Persist and Recover State

As a user,
I want session state to persist across daemon restarts,
So that workflows can resume without losing progress.

**Acceptance Criteria:**

**Given** a running session
**When** the daemon restarts
**Then** session state is recovered from storage
**And** tmux sessions remain attached
**And** workflow resumes from the last checkpoint
**And** session→thread mapping is persisted in SQLite (`langgraph_sessions` table)

### Story 1.7: LangGraph Infrastructure Setup

As a user,
I want LangGraph service running and accessible,
So that smart intervention and workflow intelligence are available.

**Acceptance Criteria:**

**Given** the project structure
**When** LangGraph infrastructure is set up
**Then** `langgraph/` directory exists with project structure
**And** `langgraph.json` configures the workflow graph
**And** `docker-compose.yml` includes LangGraph service on port 8123
**And** health endpoint `GET /info` returns 200
**And** Elixir client can connect and create threads

### Story 1.8: Elixir LangGraph Client

As a developer,
I want an Elixir client module for LangGraph API,
So that Elixir can manage workflow threads and runs.

**Acceptance Criteria:**

**Given** LangGraph service is running
**When** Elixir calls the client
**Then** `Babysitter.LangGraphClient` can create threads
**And** can start/stop runs with input payloads
**And** can poll run status
**And** can resume after interrupt
**And** handles errors with 3x retry + exponential backoff

---

## Epic 2: Connecting Tools

### Story 2.1: Read Issues from td

As a user,
I want babysitter to read issues from td's SQLite database,
So that workflows can access issue context and work items.

**Acceptance Criteria:**

**Given** td has issues in `.todos/issues.db`
**When** babysitter queries for issues
**Then** issues are returned with title, description, status, and handoff context
**And** queries support filtering by status, type, priority

### Story 2.2: Write Context to td

As a user,
I want babysitter to write handoffs, logs, and review status back to td,
So that the next session knows what was done and what remains.

**Acceptance Criteria:**

**Given** a session completes or escalates
**When** babysitter writes to td
**Then** handoff is created with done/remaining/uncertain fields
**And** logs are added to the issue
**And** review status is updated

### Story 2.3: Configure Commit Strategy

As a user,
I want to configure when and how commits are made,
So that work is saved according to my team's workflow.

**Acceptance Criteria:**

**Given** git configuration in `.babysitter/config.yaml`
**When** a stage completes
**Then** commits are made according to the configured trigger (stage_complete, validation_pass, manual)
**And** commit messages use the configured template

### Story 2.4: Create Pull Requests

As a user,
I want babysitter to create PRs when workflows complete,
So that changes are ready for human review.

**Acceptance Criteria:**

**Given** a workflow completes successfully
**When** PR trigger is configured
**Then** a PR is created with title, body, and labels from templates
**And** reviewers are assigned if configured

---

## Epic 3: Quality Gates

### Story 3.1: Run Validation Commands

As a user,
I want validation commands to run after stages,
So that quality gates can block progression on failure.

**Acceptance Criteria:**

**Given** a stage with validation configured
**When** the stage completes
**Then** compile validation runs `mix compile` / `go build` / `npm run build`
**And** test validation runs `mix test` / `go test` / `pytest`
**And** custom commands execute with exit code determining pass/fail

---

## Epic 4: Monitoring & Control

### Story 4.1: Real-time TUI Display

As a user,
I want to see session progress in real-time,
So that I can monitor work as it happens.

**Acceptance Criteria:**

**Given** sessions are running
**When** the TUI is open
**Then** session list shows active sessions with status
**And** output streams live via WebSocket
**And** updates appear within 1 second

### Story 4.2: Dumb Intervention

As a user,
I want rules-based intervention when things fail,
So that retries and escalations happen automatically.

**Acceptance Criteria:**

**Given** a session fails validation or times out
**When** dumb intervention runs
**Then** retries are applied up to max_retries
**And** escalation happens when limits are reached
**And** context is preserved for retry attempts

### Story 4.3: Smart Intervention

As a user,
I want LLM-powered analysis when things get stuck,
So that I get intelligent recovery suggestions.

**Acceptance Criteria:**

**Given** LangGraph is available (from Story 1.7)
**When** smart intervention triggers
**Then** LLM analyzes the session output
**And** recommends retry, skip, or escalate
**And** can restart with modified context

### Story 4.4: Human-in-the-Loop

As a user,
I want workflows to pause and wait for my approval,
So that I can intervene at key decision points.

**Acceptance Criteria:**

**Given** a workflow reaches an interrupt point
**When** intervention is triggered
**Then** the workflow pauses
**And** I can approve, deny, or modify via TUI
**And** workflow resumes based on my response

### Story 4.5: Attach to Session

As a user,
I want to attach to a running session for debugging,
So that I can see what the agent is doing and intervene directly.

**Acceptance Criteria:**

**Given** a session is running in tmux
**When** I click Attach in TUI
**Then** a tmux attach command is returned
**And** I can see the agent's terminal directly
