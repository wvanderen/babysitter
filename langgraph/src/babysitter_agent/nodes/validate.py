"""Validation node for the Babysitter Agent workflow.

This node runs validation commands (compile, tests, lint, custom) by calling
the Elixir validator API and returns the results.

The validation node integrates with the Elixir StageExecutor which handles
the actual command execution via tmux.
"""

import httpx
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Any, Literal
import logging

from babysitter_agent.state import AgentState

logger = logging.getLogger(__name__)

ValidationType = Literal["compile", "tests", "lint", "command"]
ValidationStatus = Literal["pass", "fail", "error", "skipped"]


@dataclass
class ValidationConfig:
    """Configuration for a validation to run.

    Attributes:
        validation_type: Type of validation (compile, tests, lint, command)
        cwd: Working directory for the command
        timeout: Timeout in milliseconds
        command: Custom command (for command/lint types)
        language: Force a specific language (elixir, go, typescript, rust)
        framework: Force a specific framework (mix, npm, pytest, go)
        env: Environment variables to set
        session_id: Associated session ID for context
        stage_id: Associated stage ID for result storage
    """

    validation_type: ValidationType
    cwd: str | None = None
    timeout: int | None = None
    command: str | None = None
    language: str | None = None
    framework: str | None = None
    env: dict[str, str] | None = None
    session_id: str | None = None
    stage_id: str | None = None


@dataclass
class ValidationResult:
    """Result of a validation run.

    Attributes:
        validation_type: Type of validation that was run
        status: Result status (pass, fail, error, skipped)
        output: Command output
        exit_code: Command exit code
        error: Error message if status is error
        started_at: When validation started
        finished_at: When validation finished
        duration_ms: Duration in milliseconds
        session_id: Associated session ID
        stage_id: Associated stage ID
    """

    validation_type: ValidationType
    status: ValidationStatus
    started_at: datetime
    finished_at: datetime
    output: str = ""
    exit_code: int | None = None
    error: str | None = None
    duration_ms: int | None = None
    session_id: str | None = None
    stage_id: str | None = None

    @property
    def passed(self) -> bool:
        """Check if the validation passed."""
        return self.status == "pass"


DEFAULT_ELIXIR_API_URL = "http://127.0.0.1:4001"
VALIDATION_TIMEOUT = 300.0


def validate_node(state: AgentState) -> dict[str, Any]:
    """Run pending validations and return results.

    This node processes all pending validations from the state,
    calls the Elixir validator API for each, and accumulates results.

    Args:
        state: Current agent state containing pending_validations

    Returns:
        State update with validation_results and cleared pending_validations
    """
    pending = state.get("pending_validations", [])
    api_base_url = state.get("elixir_api_base_url", DEFAULT_ELIXIR_API_URL)

    if not pending:
        logger.debug("No pending validations to run")
        return {"validation_results": [], "pending_validations": []}

    results = []
    for validation_config in pending:
        config = ValidationConfig(
            validation_type=validation_config.get("validation_type", "command"),
            cwd=validation_config.get("cwd"),
            timeout=validation_config.get("timeout"),
            command=validation_config.get("command"),
            language=validation_config.get("language"),
            framework=validation_config.get("framework"),
            env=validation_config.get("env"),
            session_id=validation_config.get("session_id"),
            stage_id=validation_config.get("stage_id"),
        )

        result = _run_single_validation(config, api_base_url)
        results.append(asdict(result))

        logger.info(
            f"Validation {config.validation_type} {result.status}: "
            f"session={config.session_id}, stage={config.stage_id}"
        )

    return {
        "validation_results": results,
        "pending_validations": [],
    }


def _run_single_validation(
    config: ValidationConfig, api_base_url: str
) -> ValidationResult:
    """Run a single validation by calling the Elixir API.

    Args:
        config: Validation configuration
        api_base_url: Base URL for the Elixir API

    Returns:
        ValidationResult with the outcome
    """
    started_at = datetime.now(timezone.utc)

    try:
        result = _call_elixir_validation_api(config, api_base_url)
        finished_at = datetime.now(timezone.utc)
        duration_ms = int((finished_at - started_at).total_seconds() * 1000)

        return ValidationResult(
            validation_type=config.validation_type,
            status=result.get("status", "error"),
            output=result.get("output", ""),
            exit_code=result.get("exit_code"),
            error=result.get("error"),
            started_at=started_at,
            finished_at=finished_at,
            duration_ms=duration_ms,
            session_id=config.session_id,
            stage_id=config.stage_id,
        )
    except httpx.TimeoutException:
        finished_at = datetime.now(timezone.utc)
        return ValidationResult(
            validation_type=config.validation_type,
            status="error",
            error=f"Validation timed out after {config.timeout or VALIDATION_TIMEOUT}s",
            started_at=started_at,
            finished_at=finished_at,
            session_id=config.session_id,
            stage_id=config.stage_id,
        )
    except Exception as e:
        finished_at = datetime.now(timezone.utc)
        logger.exception(f"Validation failed with exception: {e}")
        return ValidationResult(
            validation_type=config.validation_type,
            status="error",
            error=str(e),
            started_at=started_at,
            finished_at=finished_at,
            session_id=config.session_id,
            stage_id=config.stage_id,
        )


def _call_elixir_validation_api(
    config: ValidationConfig, api_base_url: str
) -> dict[str, Any]:
    """Call the Elixir validation API endpoint.

    Args:
        config: Validation configuration
        api_base_url: Base URL for the Elixir API

    Returns:
        Response dict with status, output, exit_code, error
    """
    endpoint = f"{api_base_url}/api/validations/run"

    payload = {
        "type": config.validation_type,
        "cwd": config.cwd,
        "timeout": config.timeout,
        "command": config.command,
        "language": config.language,
        "framework": config.framework,
        "env": config.env,
        "session_id": config.session_id,
        "stage_id": config.stage_id,
    }
    payload = {k: v for k, v in payload.items() if v is not None}

    timeout = (config.timeout / 1000.0) if config.timeout else VALIDATION_TIMEOUT

    with httpx.Client(timeout=timeout) as client:
        response = client.post(endpoint, json=payload)
        response.raise_for_status()
        return response.json()


def determine_validation_action(state: AgentState) -> str:
    """Determine what action to take based on validation state.

    This is a conditional edge function that routes based on:
    - pending_validations present -> "validate"
    - failed validations in results -> "intervene"
    - otherwise -> "no_validation"

    Args:
        state: Current agent state

    Returns:
        Action string: "validate", "intervene", or "no_validation"
    """
    pending = state.get("pending_validations", [])
    results = state.get("validation_results", [])

    if pending:
        return "validate"

    for result in results:
        if result.get("status") in ("fail", "error"):
            return "intervene"

    return "no_validation"
