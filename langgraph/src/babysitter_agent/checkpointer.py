"""SqliteSaver configuration for LangGraph checkpointing."""

import os
from pathlib import Path

from langgraph.checkpoint.sqlite import SqliteSaver


def get_checkpointer():
    """Get the checkpointer for persisting workflow state.

    Uses SqliteSaver with a persistent database file.
    The database path is configured via LANGGRAPH_DATA_DIR env var.
    """
    db_path = get_sqlite_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    return SqliteSaver.from_conn_string(str(db_path))


def get_sqlite_path() -> Path:
    """Get the path for the SQLite checkpoint database."""
    base_dir = Path(os.environ.get("LANGGRAPH_DATA_DIR", "data"))
    return base_dir / "langgraph" / "checkpoints.db"
