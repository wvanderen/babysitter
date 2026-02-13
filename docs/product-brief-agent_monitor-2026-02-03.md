---
stepsCompleted: [1, 2, 3, 4, 5]
inputDocuments: ["project-context.md", "docs/index.md", "docs/project-overview.md", "docs/architecture.md", "docs/development-guide.md", "docs/api-contracts.md", "docs/source-tree-analysis.md"]
date: 2026-02-03
author: Lem
---

# Product Brief: agent_monitor

## Executive Summary

An open-source Elixir framework for orchestrating AI agents across software development workflows, treating agent methodology orchestration as a first-class concern. The platform bridges planning (BMAD) and execution (Ralph) with intelligent supervision, multi-layer validation, and overnight autonomy—enabling developers to define requirements before bed and wake up to working software.

Unlike existing tools that handle generic workflow orchestration, this framework understands software engineering semantics and provides methodology-agnostic "methodology packs" (BMAD, Ralph, custom) that can be swapped like tools in a developer's kit.

---

## Core Vision

### Problem Statement

Developers using AI coding tools face a critical orchestration gap: powerful methodologies exist (BMAD for structured planning, Ralph Wiggum loops for iterative execution), but coordinating between them requires manual friction, scattered context across multiple terminals, and constant vigilance.

Key pain points:
- **Manual coordination**: Flow charts, sprint-status.yaml files, and multiple terminals must be consulted manually
- **False completion problem**: Agents frequently claim completion (DONE promise) when work is unfinished—exiting loops prematurely
- **Validation gaps**: No automated validation layers for compile checks, test passing, browser-based verification, manual inspection, and code review
- **Mental energy drain**: "Taking in all information about what's happening" across systems is exhausting
- **Failure handling**: OOM crashes and other failures halt workflows without intelligent remediation
- **No project intelligence**: Can't navigate project "DNA"—zoom from vision through architecture down to components
- **No autonomy**: Can't set workflows running overnight and trust they'll self-correct

### Problem Impact

Developers are bottlenecked by orchestration friction rather than engineering challenges. The promise of "go to bed, wake up to sophisticated software" remains unrealized because tools execute tasks but don't govern the process. Each manual check—"Is it compiling?", "Did tests pass?", "Does it work in a browser?", "What's current status?"—interrupts flow and consumes cognitive bandwidth.

False completion is particularly insidious: agents exit early leaving half-built features, unconnected code, or missing user interfaces—requiring manual discovery and restarting loops. OOM crashes aren't just annoyances; they're workflow stoppers that require manual diagnosis and relaunching.

### Why Existing Solutions Fall Short

| Solution | Gap |
|-----------|-------|
| **Conductor** | Infrastructure orchestration (scheduling, scaling) but no methodology awareness |
| **OpenAI Codex App** | Polished end-to-end experience but closed ecosystem, locked into vendor, no BMAD/Ralph bridging |
| **LangChain / LangGraph** | Generic workflow graphs, no understanding of software engineering semantics |
| **BMAD alone** | Structured methodology but manual phase-to-phase coordination |
| **Ralph alone** | Brute force persistence, no methodology context, no intelligent validation |

None treat agent methodology orchestration as a first-class concern. They orchestrate *tasks*, not *methodologies*—missing the semantic context that makes software engineering workflows actually work.

### Proposed Solution

An Elixir-based open-source framework that orchestrates AI agents with methodology-agnostic supervision, multi-layer validation, and overnight autonomy.

**Core architecture:**
- **Methodology packs**: Swappable modules (BMAD, Ralph, custom) that declare their validation interfaces
- **Agent loop primitive**: Ralph-style persistent iteration with visibility, connected via workflows, validated at completion
- **Zoom system**: Project DNA navigation from vision → architecture → components, surfacing right detail at right time
- **Intelligent supervision**: Elixir supervision trees treat agent failure as expected, not exceptional—with autonomous remediation
- **Multi-layer validation gates**: Compile checks, test passing, browser verification, manual inspection, code review—all must pass before completion accepted
- **Dashboard**: Real-time view of running processes, current steps, struggling agents, attention requests
- **Autopilot**: Human-supervision proxy that intelligently nudges stuck workflows during overnight runs

**Methodology pack abstraction (Elixir protocols):**
```elixir
defprotocol Methodology do
  def validate_completion(state, artifact)
  def escalation_triggers(state)
  def context_requirements(step)
end
```

BMAD and Ralph implement this protocol differently, but orchestration layer works with the contract—enabling hot-swappable methodologies without rewriting core engine.

### Key Differentiators

1. **Methodology-agnostic orchestration as first-class concern**: First framework to treat agent methodology orchestration as fundamental, not bolted-on task management

2. **Elixir's fault tolerance as feature**: Supervision trees treat agent crashes as expected—restart with modified context, exponential backoff, circuit breakers. OOM crashes trigger autonomous remediation, not just loop restart

3. **False completion detection and correction**: Multi-layer validation (compile, tests, browser, manual, code review) prevents agents from claiming DONE when work is unfinished

4. **Zoom system for project navigation**: Navigate project DNA across granularities—from high-level vision down to individual components—surfacing right context when needed

5. **Overnight autonomy with autopilot**: Go to bed with requirements tuned; wake up to 10 completed stories forming working software. Autopilot intelligently handles escalation when human is away

6. **Modular, open-source philosophy**: Everything is swappable—models, tools, processes, development philosophies—like bringing your kit to different jobs. Build-for-self-first, useful to everyone

7. **Semantic understanding of software engineering**: Knows that BMAD `/create-architecture` outputs structured artifacts that subsequent steps must validate against—unlike generic workflow engines

8. **Intelligent failure handling**: Not just restart on crash, but remediate cause while workflow continues. OOM crashes trigger autonomous analysis and context reduction, not just loop restart

**Unfair advantage**: You're solving a problem you live daily, with deep expertise in BMAD methodology, Ralph loop patterns, and Elixir's unique strengths. The combination of real-world pain + technical elegance creates genuine differentiation.

---

## Success Metrics

### User Success Metrics

**Workflow Autonomy:**
- **Autonomy percentage** - (workflow hours autonomous) / (total workflow hours) — measures how much work happens without manual intervention

**Navigation Efficiency:**
- **Time to project status** - Average time to determine "where are we?" for active workflows (target: <30 seconds)
- **"3-click zoom" improvement** - Time saved by using zoom navigation vs. manual file navigation (baseline: existing manual navigation time)

**Setup & Onboarding:**
- **Time to first autonomous workflow** - From installation/configuration to successfully running autonomous overnight workflow (target: <2 hours)
- **Methodology pack configuration time** - Time to configure BMAD/Ralph/custom methodology packs (target: <15 minutes)

**Solo Founder Dashboard Clarity:**
- **Morning comprehension time** - Time for solo founder to understand dashboard status and determine action items upon waking up (target: <5 minutes)
- **Overnight workflow success rate** - % of overnight workflows that complete successfully without morning intervention (target: >90%)

### Accuracy & Quality Metrics

**False Completion Rate:**
- **False completion rate** - % of workflows where agents claim DONE but work is incomplete or fails validation
  - Measure by tracking DONE claims vs. validation gate results
  - Target: <5%

**Validation Gate Pass Rate:**
- **Pass-all rate** - % of workflows that pass ALL validation gates (compile, tests, browser, manual, code review)
  - All gates must pass before completion accepted
  - Target: >95%
- **Average validation pass rate** - % of individual validation gates that pass per workflow

**Crash Remediation:**
- **Level 1 completion rate** - % of crashes that achieve basic remediation (identify + restart + continue workflow)
  - Target: >80%
- **Level 2 completion rate** - % of crashes that achieve advanced remediation (analyze cause + fix environment issue + prevent recurrence)
  - Target: >50%
- **OOM crash remediation time** - Average time from OOM crash to workflow resumption (target: <5 minutes)

### Efficiency & Velocity Metrics

**Time to Information:**
- **Project status lookup time** - Average time to find current state of any running workflow (target: <60 seconds)

**Stories Completed Per Week:**
- **Weekly story completion rate** - Average stories completed successfully per week
  - Baseline: Existing team throughput (from Jira/story points)
  - Target: 25% improvement over baseline

**Baseline Improvement:**
- **Story point velocity change** - % improvement in story point completion rate from pre-orchestration to post-orchestration period
  - Measure using existing team metrics (two-week sprints)
  - **Churn rate reduction** - % reduction in average time stories stay in active status
  - Lower churn indicates smoother workflows

### Business Impact Metrics

**Team Capacity Freed:**
- **Hours reclaimed for strategic work** - Total hours redirected from manual orchestration/friction to strategic initiatives per month
  - Measure by tracking time spent on manual coordination before vs. after

**Technical Debt Reduction:**
- **Technical debt resolution hours** - Total hours spent resolving technical debt via orchestrated workflows per month
  - Track hours saved vs. manual cleanup (example: console log cleanup, service worker fix = 8 hours saved)

**Performance Improvement:**
- **Performance metric improvement** - % improvement in key performance metrics (latency, throughput, resource usage) from orchestrated remediation
  - Example: Service worker optimization resulting in 40% performance boost

### Setup & Adoption Metrics

**Methodology Pack Adoption:**
- **Methodology packs in use** - Count of methodology packs (BMAD, Ralph, custom) actively configured
- **New methodology pack time** - Average time to configure a new methodology pack (target: <20 minutes)

**Solo Founder Reconfiguration Frequency:**
- **Orchestration reconfiguration rate** - Times per month solo founder needs to manually adjust orchestration settings
  - Target: <1 time/month (lower = better "set it once" experience)

**Open Source Community Engagement:**
- **GitHub stars** - Track repository popularity
- **Issue resolution time** - Average time to resolve community-reported issues
- **Contributor growth** - Number of active contributors per month

### Key Performance Indicators

**Primary KPIs (North Star Metrics):**

1. **Overnight Autonomy Score** - Composite score combining autonomy percentage, overnight success rate, and false completion rate
   - Formula: (Autonomy % × 0.4) + (Overnight Success % × 0.4) - (False Completion % × 0.2)
   - Target: >75

2. **Workflow Efficiency Index** - Time to information + stories per week + baseline improvement
   - Target: Top 20% in improvement over baseline

3. **Orchestration Reliability** - Level 2 crash remediation rate + pass-all validation rate
   - Target: >85%

**Secondary KPIs (Operational Metrics):**

- Setup friction: Time to first autonomous workflow (<2 hours target)
- Dashboard clarity: Morning comprehension time (<5 minutes target)
- False completion incidents per month: Track and target <5

**Measurement Methods:**

- **Autonomy percentage**: Track workflow timestamps, calculate (autonomous minutes) / (total minutes)
- **Validation gates**: Automated tracking of each gate (compile, tests, browser, manual, code review) with pass/fail
- **Baseline comparison**: Leverage existing Jira/story point metrics for before/after measurement
- **Crash remediation levels**: Categorize each crash remediation as Level 1 or Level 2
- **Business impact**: Track hours saved via orchestration, correlate with team strategic output

### Business Objectives

N/A - This is a framework project being built for personal use and open-source distribution, not a traditional business product with revenue/commercial objectives.

Success will be measured by:
- Open-source community adoption (GitHub stars, forks, contributors)
- User testimonials and success stories
- Framework adoption by developers and teams

---

## MVP Scope

### Core Features

**Orchestration Core**
- Framework that chains, organizes, and runs workflows autonomously
- Methodology pack system (BMAD, Ralph, custom) with hot-swappable interfaces
- Workflow definition and execution engine with state tracking
- Multi-layer validation gates (compile, tests, browser, manual, code review)

**Agent Engagement**
- False completion detection and restart - Identifies when agents claim DONE but work is incomplete or fails validation
- OOM crash remediation - Two-level recovery:
  - Level 1: Basic restart and continue workflow
  - Level 2: Analyze cause, fix environment issue, prevent recurrence, resume workflow
- Stuck workflow nudging (Autopilot) - Intelligent escalation when workflows aren't progressing
- Agent that monitors active workflows and can intervene or re-route

**Project Intelligence Dashboard**
- Unified view of all project aspects: stories, tasks, architecture, components
- Metrics tracking tied to project data (not isolated dashboards)
- Zoom navigation from project vision → architecture → individual components
- Real-time status of running workflows and their validation gate results
- Requirements mapped to decisions and artifacts showing traceability

### Out of Scope for MVP

**Advanced Validation Layers (deferred to post-MVP):**
- Browser-based automation validation
- Sophisticated code review agents
- Advanced multi-tenant/SaaS capabilities
- Custom methodology pack creation UI with visual workflow builder
- Marketplace for sharing methodology packs and validation strategies

**Multi-tenant/SaaS Capabilities (deferred):**
- Multi-project orchestration across teams
- Centralized metrics and analytics
- Team management and permission controls
- Advanced security and isolation

**Marketplace (deferred):**
- Community-driven methodology pack sharing
- Downloadable validation strategies and agent configurations
- User-contributed custom methodologies
- Plugin system for extending core framework
- Documentation for creating custom methodology packs

### MVP Success Criteria

**User Adoption Metrics:**
- 10+ active workflows configured within first month
- Successful overnight runs (90%+ completion rate without manual intervention)
- Average project status lookup time <30 seconds
- Time to first autonomous workflow <2 hours
- Time to configure BMAD/Ralph/custom methodology packs <15 minutes

**Problem Validation:**
- Demonstrated false completion detection and recovery in real-world scenario
- OOM crash remediation working in tests
- Autopilot successfully nudges stuck workflows
- Pass-all validation rate >95% across test workflows
- False completion rate <5%

**Quality Metrics:**
- Pass-all validation rate >95% across test workflows
- Average validation pass rate >90%
- OOM crash remediation Level 2 >50%
- Workflow autonomy percentage >75%

### Future Vision

**Post-MVP Enhancements:**
These capabilities build upon MVP foundation and will be prioritized based on user feedback and adoption metrics:

**Advanced Validation Integration**
- Browser-based test automation (Playwright, Puppeteer integration)
- Sophisticated code review agents with pattern detection and security analysis
- Dynamic test generation based on code changes
- Performance profiling and optimization suggestions

**Custom Methodology Pack Creation UI**
- Visual workflow builder with drag-and-drop interface
- No-code methodology pack configuration
- Export/import methodology packs for sharing
- Version control integration for methodology packs
- Documentation for creating custom methodology packs

**Multi-tenant Architecture**
- Multi-project support with isolated workspaces
- Team management with role-based permissions (admin, developer, viewer)
- Centralized analytics dashboard across all projects
- Audit logs and workflow history per project
- Integration with external AI providers (beyond single LLM)

**Community Ecosystem**
- Open marketplace for methodology packs (BMAD, Ralph, and community contributions)
- Plugin system for framework extensions (dashboard widgets, custom validators)
- Documentation for creating and sharing custom methodologies
- Contribution metrics and recognition for methodology authors
- Community-driven validation strategy improvements

**Scalability & Performance**
- Horizontal scaling across multiple Elixir nodes
- Workflow optimization and caching
- Resource pooling and load balancing
- Integration with external AI providers for scalability

Success will be measured by:
- Open-source community adoption (GitHub stars, forks, contributors)
- User testimonials and success stories
- Framework adoption by developers and teams
