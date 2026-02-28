"""State definitions for the Babysitter Agent workflow."""

from typing import Annotated, Any, TypedDict
from operator import add


class SessionState(TypedDict):
    """State for a single monitored session."""

    session_id: str
    status: str
    output_buffer: Annotated[list[str], add]
    metadata: dict[str, Any]


class AgentState(TypedDict):
    """Main state for the Babysitter Agent workflow."""

    sessions: dict[str, SessionState]
    intervention_history: Annotated[list[dict[str, Any]], add]
    current_analysis: str | None
    pending_action: dict[str, Any] | None
    pending_validations: list[dict[str, Any]]
    validation_results: Annotated[list[dict[str, Any]], add]
    elixir_api_base_url: str
