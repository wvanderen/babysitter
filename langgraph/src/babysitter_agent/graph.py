"""Main workflow graph for the Babysitter Agent."""

from langgraph.graph import StateGraph, END

from babysitter_agent.state import AgentState
from babysitter_agent.checkpointer import get_checkpointer
from babysitter_agent.nodes.validate import (
    validate_node,
    determine_validation_action,
)


def analyze_sessions(state: AgentState) -> dict:
    """Placeholder node: Analyze session states for intervention needs."""
    return {"current_analysis": None}


def determine_action(state: AgentState) -> str:
    """Placeholder conditional edge: Determine if action is needed."""
    pending = state.get("pending_validations", [])
    if pending:
        return "validate"
    return "no_action"


def create_intervention(state: AgentState) -> dict:
    """Placeholder node: Create an intervention action."""
    return {"pending_action": None}


def record_intervention(state: AgentState) -> dict:
    """Placeholder node: Record intervention in history."""
    return {"intervention_history": []}


def build_graph() -> StateGraph:
    """Build the Babysitter Agent workflow graph.

    The graph supports validation workflows:
    - analyze -> determine_action (routes to validate or END)
    - validate -> determine_validation_action (routes to intervene or END)
    - intervene -> record -> END
    """
    graph = StateGraph(AgentState)

    graph.add_node("analyze", analyze_sessions)
    graph.add_node("validate", validate_node)
    graph.add_node("intervene", create_intervention)
    graph.add_node("record", record_intervention)

    graph.set_entry_point("analyze")

    graph.add_conditional_edges(
        "analyze",
        determine_action,
        {
            "validate": "validate",
            "action_needed": "intervene",
            "no_action": END,
        },
    )

    graph.add_conditional_edges(
        "validate",
        determine_validation_action,
        {
            "validate": "validate",
            "intervene": "intervene",
            "no_validation": END,
        },
    )

    graph.add_edge("intervene", "record")
    graph.add_edge("record", END)

    return graph


def get_compiled_graph():
    """Get the compiled graph with checkpointer."""
    graph = build_graph()
    checkpointer = get_checkpointer()
    return graph.compile(checkpointer=checkpointer)
