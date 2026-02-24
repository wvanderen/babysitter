---
stepsCompleted: [1, 2]
inputDocuments: []
workflowType: 'research'
lastStep: 2
research_type: 'technical'
research_topic: 'LangGraph Integration'
research_goals: 'Research how to wire Go TUI ↔ Elixir ↔ LangGraph service, focusing on: deployment options, state management/checkpointing, human-in-the-loop patterns, MCP adapters for tools'
user_name: 'Lem'
date: '2026-02-24'
web_research_enabled: true
source_verification: true
---

# Research Report: Technical - LangGraph Integration

**Date:** 2026-02-24
**Author:** Lem
**Research Type:** technical

---

## Technical Research Scope Confirmation

**Research Topic:** LangGraph Integration
**Research Goals:** Research how to wire Go TUI ↔ Elixir ↔ LangGraph service, focusing on: deployment options, state management/checkpointing, human-in-the-loop patterns, MCP adapters for tools

**Technical Research Scope:**

- Architecture Analysis - design patterns, frameworks, system architecture
- Implementation Approaches - development methodologies, coding patterns
- Technology Stack - languages, frameworks, tools, platforms
- Integration Patterns - APIs, protocols, interoperability
- Performance Considerations - scalability, optimization, patterns

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-02-24

---

## Executive Summary

LangGraph is a framework for building stateful, multi-actor AI applications with resilient agent workflows. For the babysitter project (Go TUI ↔ Elixir/Phoenix ↔ LangGraph), the recommended architecture is:

**Recommended Architecture:**
```
Go TUI (WebSocket Client) ↔ Elixir/Phoenix (WebSocket Server + API Gateway) ↔ LangGraph Platform (Python Service)
```

**Key Findings:**
1. **Deployment:** LangGraph Platform (now LangSmith Deployment) offers Cloud SaaS, Self-Hosted Lite (free), BYOC (AWS), and Self-Hosted Enterprise options
2. **State Management:** Built-in checkpointing with SqliteSaver/PostgresSaver enables memory, fault tolerance, and time-travel debugging
3. **Human-in-the-Loop:** `interrupt()` function with `Command` resume pattern enables approval workflows, state editing, and tool review
4. **MCP Integration:** `langchain-mcp-adapters` package bridges MCP tools to LangGraph agents
5. **Elixir Integration:** REST API + Phoenix Channels WebSocket protocol is the recommended integration path

---

## 1. LangGraph Platform Deployment Options

### 1.1 Deployment Models (Confidence: HIGH - Official LangChain docs)

| Option | Description | Cost | Best For |
|--------|-------------|------|----------|
| **Cloud SaaS** | Fully managed, auto-updates, zero maintenance | LangSmith Plus/Enterprise | Production, no ops overhead |
| **Self-Hosted Lite** | Free, up to 1M nodes executed | Free | Development, testing |
| **BYOC (AWS)** | Runs in your VPC, managed provisioning | Enterprise | Compliance, data residency |
| **Self-Hosted Enterprise** | Full control on own infrastructure | Enterprise license | Complete autonomy |

### 1.2 Self-Hosting Without Enterprise License

LangGraph is open-source. Basic self-hosting options:
- **Docker containers** via `langgraph-cli`
- **FastAPI** to expose as REST endpoints
- **BentoML** for containerized AI inference services
- **Render.com, Fly.io** for simple Docker deployments

**Caveat:** Self-hosting requires managing:
- Authentication & security
- Rate limiting
- State persistence (Redis/PostgreSQL)
- Horizontal scaling

### 1.3 Key Platform Features

- **30 API endpoints** for custom UX
- **Horizontal scaling** for high traffic
- **Persistence layer** for memory/conversation history
- **LangGraph Studio** integration for debugging
- **1-click deployment** from GitHub

### 1.4 Recommendation for Babysitter

**Option A (Recommended for MVP):** Self-Hosted Lite or Docker deployment
- Zero cost for development
- SQLite checkpointer sufficient for single-tenant use
- Can upgrade to Cloud SaaS later

**Option B (Production):** Cloud SaaS or BYOC
- Automatic scaling and updates
- Built-in observability with LangSmith

---

## 2. State Management & Checkpointing

### 2.1 Core Concepts (Confidence: HIGH - Official docs)

**StateGraph:** The graph manages state as a shared data structure. Nodes are Python functions that:
1. Receive current state
2. Perform operations (LLM calls, business logic)
3. Return updated state

**Checkpoint:** Complete snapshot saved at every "super-step" (after each node execution):
- **Values:** Current state of all channels
- **Next nodes:** Scheduled execution targets
- **Tasks:** Pending operations/error info
- **Config:** Thread ID, checkpoint ID
- **Metadata:** Timing and contextual info

**Thread:** Unique identifier for each conversation/run sequence. Required for checkpointing.

### 2.2 Checkpointer Options

| Checkpointer | Persistence | Use Case |
|--------------|-------------|----------|
| `MemorySaver` | In-memory (process-bound) | Development only |
| `SqliteSaver` | SQLite file | Single-instance, dev/staging |
| `PostgresSaver` | PostgreSQL | **Production recommended** |
| `Couchbase` | Distributed | Enterprise scale |

### 2.3 Memory Types

- **Short-term memory:** Thread-scoped state via checkpointers
- **Long-term memory:** Cross-thread sharing via `Store` interface (`PostgresStore`, `RedisStore`)

### 2.4 Benefits

1. **Memory:** Agents remember past states across interactions
2. **Fault Tolerance:** Resume from last checkpoint after crash
3. **Time Travel:** Rewind to any previous checkpoint for debugging/replay
4. **HITL Foundation:** Enables pause/resume for human intervention

### 2.5 Recommendation for Babysitter

```python
from langgraph.checkpoint.sqlite import SqliteSaver

# For MVP - simple file-based persistence
checkpointer = SqliteSaver.from_conn_string("babysitter_checkpoints.db")

# For production - PostgreSQL
from langgraph.checkpoint.postgres import PostgresSaver
checkpointer = PostgresSaver(conn_string)
```

Use `thread_id` mapped to babysitter session ID for state correlation.

---

## 3. Human-in-the-Loop (HITL) Patterns

### 3.1 Core Mechanism: `interrupt()` (Confidence: HIGH)

```python
from langgraph.types import interrupt

def approval_node(state):
    # Pause execution and wait for human input
    user_decision = interrupt({
        "type": "approval_required",
        "message": "Approve this action?",
        "context": state["pending_action"]
    })
    
    if user_decision == "approved":
        return {"status": "proceed"}
    else:
        return {"status": "cancelled"}
```

### 3.2 Resume Pattern

```python
from langgraph.types import Command

# Resume with user's decision
graph.invoke(
    Command(resume="approved"),
    config={"configurable": {"thread_id": "session-123"}}
)
```

### 3.3 HITL Patterns

| Pattern | Use Case | Implementation |
|---------|----------|----------------|
| **Approve/Reject** | Critical decisions before LLM/tool calls | `interrupt()` before action |
| **Review & Edit State** | Human modifies agent state | Return modified state via `Command` |
| **Review Tool Calls** | Approve/edit/reject tool invocations | `interrupt()` with tool details |
| **Validate Input** | Ensure data quality before processing | Loop with `interrupt()` until valid |
| **Debugging** | Dynamic breakpoints | `interrupt()` at inspection points |

### 3.4 Static Interrupts

Configure automatic pauses at specific nodes:
```python
graph.compile(
    interrupt_before=["sensitive_action"],  # Pause BEFORE node
    interrupt_after=["llm_call"]            # Pause AFTER node
)
```

### 3.5 Critical Considerations

⚠️ **Idempotency:** When resuming, the node re-executes from the beginning. Code before `interrupt()` must be idempotent.

⚠️ **Error Handling:** Do NOT wrap `interrupt()` in try/except blocks.

⚠️ **Payload:** Must be JSON-serializable.

### 3.6 Recommendation for Babysitter

For the Go TUI ↔ Elixir ↔ LangGraph flow:

1. **Elixir receives user action** → sends to LangGraph via REST
2. **LangGraph reaches `interrupt()`** → returns interrupt info in response
3. **Elixir pushes interrupt to TUI** via WebSocket (Phoenix Channel)
4. **User responds in TUI** → Elixir sends `Command(resume=...)` to LangGraph
5. **LangGraph continues** → returns result to Elixir → TUI

---

## 4. MCP (Model Context Protocol) Adapters

### 4.1 What is MCP? (Confidence: HIGH)

Developed by Anthropic, MCP is an open protocol for AI models to communicate with external tools/data sources in a standardized way.

**Architecture:**
- **MCP Server:** Exposes tools (functions) to AI
- **MCP Client:** Connects AI model to servers
- **Standardized JSON patterns** for tool communication

### 4.2 LangGraph MCP Integration

The `langchain-mcp-adapters` package (Python & JavaScript) converts MCP tools to LangChain/LangGraph compatible format.

```python
from langchain_mcp_adapters import load_mcp_tools

# Load tools from MCP server
tools = await load_mcp_tools(mcp_client)

# Use in LangGraph agent
agent = create_react_agent(llm, tools)
```

### 4.3 Tool Examples

- Mathematical functions
- Weather data retrieval
- Database querying
- File system access
- Third-party integrations (Gmail, GitHub, etc.)

### 4.4 Benefits

- **Modularity:** Plug-and-play tool integration
- **Reusability:** Same MCP server works with multiple AI frameworks
- **Context Awareness:** Enhanced state sharing between tools and agents

### 4.5 Recommendation for Babysitter

If the babysitter agent needs external tools:
1. Define babysitter-specific tools as MCP server
2. Use `langchain-mcp-adapters` to integrate with LangGraph agent
3. Tools could include: tmux commands, file operations, session management

---

## 5. Elixir/Phoenix ↔ LangGraph Integration

### 5.1 Integration Architecture (Confidence: HIGH)

**Recommended Pattern:**
```
┌─────────────┐     WebSocket      ┌─────────────┐     HTTP/REST     ┌─────────────┐
│   Go TUI    │ ←───────────────→ │   Phoenix   │ ←───────────────→ │  LangGraph  │
│  (Client)   │   Phoenix Channel │   Server    │   LangGraph SDK  │   Server    │
└─────────────┘                    └─────────────┘                   └─────────────┘
```

### 5.2 Communication Protocols

| Layer | Protocol | Purpose |
|-------|----------|---------|
| TUI ↔ Phoenix | WebSocket (Phoenix Channels) | Real-time bidirectional |
| Phoenix ↔ LangGraph | HTTP REST | Request/response |
| Alternative | gRPC | High-performance (optional) |

### 5.3 Phoenix Channels Protocol

The Go TUI already implements Phoenix Channels protocol:
```json
{"topic": "session:<id>", "event": "phx_join", "payload": {}, "ref": "1"}
```

### 5.4 LangGraph Platform SDK

```python
from langgraph_sdk import get_client

# Connect to LangGraph server
client = get_client(url="http://localhost:8123")

# Create thread (conversation)
thread = await client.threads.create()

# Invoke assistant
run = await client.runs.stream(
    thread_id=thread["thread_id"],
    assistant_id="agent",
    input={"messages": [{"role": "user", "content": "..."}]}
)
```

### 5.5 Elixir HTTP Client to LangGraph

```elixir
defmodule Babysitter.LangGraphClient do
  use Tesla
  
  plug Tesla.Middleware.BaseUrl, "http://localhost:8123"
  plug Tesla.Middleware.JSON
  
  def create_thread do
    post("/threads", %{})
  end
  
  def invoke_agent(thread_id, input) do
    post("/threads/#{thread_id}/runs/stream", %{
      assistant_id: "agent",
      input: input
    })
  end
  
  def resume_run(thread_id, run_id, resume_value) do
    # Resume after interrupt
    post("/threads/#{thread_id}/runs/#{run_id}", %{
      command: %{resume: resume_value}
    })
  end
end
```

### 5.6 Integration Options

| Option | Coupling | Performance | Complexity |
|--------|----------|-------------|------------|
| **REST API** | Loose | Good | Low |
| **ErlPort** | Tight | High | Medium |
| **PythonX (NIF)** | Very tight | Highest | High |
| **Message Queue** | Loose | Good | Medium |

**Recommendation:** REST API for MVP. ErlPort only if latency becomes critical.

### 5.7 State Correlation

Map babysitter session IDs to LangGraph thread IDs:
```elixir
# In Elixir session
def handle_info({:langgraph_interrupt, data}, state) do
  # Push to Go TUI via Phoenix Channel
  Babysitter.Broadcast.push_interrupt(state.id, data)
  {:noreply, state}
end
```

---

## 6. Implementation Recommendations

### 6.1 Phase 1: MVP Architecture

1. **Deploy LangGraph** as Docker container with SQLite checkpointer
2. **Elixir Phoenix** acts as API gateway to LangGraph REST endpoints
3. **Go TUI** communicates via existing Phoenix Channels
4. **Thread ID** = Babysitter Session ID for state correlation

### 6.2 Key Integration Points

```elixir
# Session creates LangGraph thread on initialization
def handle_call(:init, _from, state) do
  {:ok, thread} = LangGraphClient.create_thread()
  {:reply, :ok, %{state | langgraph_thread_id: thread["thread_id"]}}
end

# Forward user input to agent
def handle_cast({:user_input, msg}, state) do
  LangGraphClient.invoke_agent(state.langgraph_thread_id, %{
    messages: [%{role: "user", content: msg}]
  })
  {:noreply, state}
end

# Handle interrupt from agent
def handle_info({:agent_interrupt, data}, state) do
  # Push to TUI for human decision
  push_interrupt_to_tui(state.id, data)
  {:noreply, %{state | status: :awaiting_human_input}}
end
```

### 6.3 Configuration

```yaml
# LangGraph deployment
langgraph:
  server_url: "http://localhost:8123"
  assistant_id: "babysitter-agent"
  
# Checkpointer
checkpointer:
  type: sqlite  # or postgres for production
  path: ./data/checkpoints.db
```

### 6.4 Error Handling

1. **LangGraph timeout:** Return error to TUI, allow retry
2. **Interrupt timeout:** Default action after configurable delay
3. **Connection failure:** Queue messages, retry with exponential backoff

---

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Python GIL limits throughput | Medium | Use multiple LangGraph instances with load balancer |
| Network latency between services | Medium | Keep LangGraph close to Phoenix (same VPC) |
| State sync issues | High | Use thread_id correlation, implement reconciliation |
| Self-hosted ops burden | Low | Start with Self-Hosted Lite, migrate to Cloud SaaS if needed |

---

## 8. Sources

### Primary Sources (High Confidence)
- [LangChain Official Documentation](https://langchain.com) - Deployment, checkpointing, HITL
- [LangGraph SDK Reference](https://github.com/langchain-ai/langgraph) - API patterns
- [Phoenix Framework Docs](https://hexdocs.pm/phoenix) - WebSocket integration

### Secondary Sources
- Medium articles on LangGraph patterns
- GitHub repositories with integration examples
- Community discussions (Reddit, ElixirForum)

---

## 9. Next Steps

1. **Create Architecture Document** (td-a003e9) - Formalize integration design
2. **Create Epics and Stories** (td-6b97a1) - Break down implementation
3. **Prototype:** Spin up LangGraph Docker, test REST API from Elixir
4. **POC:** Implement single HITL flow through full stack

---

*Research completed: 2026-02-24*
*Confidence level: HIGH on all major findings*
