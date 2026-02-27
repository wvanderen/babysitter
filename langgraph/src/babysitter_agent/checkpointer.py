"""SqliteSaver configuration for LangGraph checkpointing."""

import os
from pathlib import Path

from langgraph.checkpoint.memory import MemorySaver


def get_checkpointer():
    """Get the checkpointer for persisting workflow state.

    Uses MemorySaver as placeholder. Will be replaced with SqliteSaver
    when configuration files are complete.
    """
    return MemorySaver()


def get_sqlite_path() -> Path:
    """Get the path for the SQLite checkpoint database."""
    base_dir = Path(os.environ.get("LANGGRAPH_DATA_DIR", "data"))
    return base_dir / "langgraph" / "checkpoints.db"
