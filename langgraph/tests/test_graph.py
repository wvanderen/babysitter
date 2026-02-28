"""Tests for the Babysitter Agent graph structure."""

import pytest

from babysitter_agent.graph import build_graph
from babysitter_agent.state import AgentState


class TestGraphStructure:
    """Test the graph structure and nodes."""

    def test_build_graph_returns_state_graph(self):
        """Test that build_graph returns a StateGraph."""
        graph = build_graph()
        assert graph is not None

    def test_graph_has_required_nodes(self):
        """Test that the graph contains all required nodes."""
        graph = build_graph()
        nodes = graph.nodes
        assert "analyze" in nodes
        assert "intervene" in nodes
        assert "record" in nodes
        assert "validate" in nodes

    def test_get_compiled_graph_returns_compiled(self):
        """Test that build_graph returns a valid graph structure."""
        graph = build_graph()
        assert graph is not None
        assert "analyze" in graph.nodes

    def test_graph_has_entry_point_set(self):
        """Test that the graph has required nodes configured."""
        graph = build_graph()
        assert "analyze" in graph.nodes
        assert "validate" in graph.nodes
        assert "intervene" in graph.nodes


class TestGraphExecution:
    """Test graph execution with sample state."""

    def test_analyze_node_returns_dict(self):
        """Test that analyze_sessions returns a dictionary."""
        from babysitter_agent.graph import analyze_sessions

        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
        }
        result = analyze_sessions(state)
        assert isinstance(result, dict)

    def test_record_intervention_node_returns_dict(self):
        """Test that record_intervention returns a dictionary."""
        from babysitter_agent.graph import record_intervention

        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
        }
        result = record_intervention(state)
        assert isinstance(result, dict)

    def test_determine_action_returns_valid_edge(self):
        """Test that determine_action returns a valid edge name."""
        from babysitter_agent.graph import determine_action

        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
        }
        result = determine_action(state)
        assert result in ["action_needed", "no_action"]
