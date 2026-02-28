"""Tests for the validate node."""

import pytest
from datetime import datetime, timezone

from babysitter_agent.nodes.validate import (
    validate_node,
    ValidationConfig,
    ValidationResult,
    determine_validation_action,
)
from babysitter_agent.state import AgentState


class TestValidationConfig:
    """Test ValidationConfig dataclass."""

    def test_create_validation_config(self):
        """Test creating a validation config."""
        config = ValidationConfig(
            validation_type="compile",
            cwd="/path/to/project",
            timeout=60000,
        )
        assert config.validation_type == "compile"
        assert config.cwd == "/path/to/project"
        assert config.timeout == 60000

    def test_validation_config_defaults(self):
        """Test validation config with default values."""
        config = ValidationConfig(validation_type="tests")
        assert config.cwd is None
        assert config.timeout is None
        assert config.command is None
        assert config.language is None


class TestValidationResult:
    """Test ValidationResult dataclass."""

    def test_passing_result(self):
        """Test creating a passing validation result."""
        result = ValidationResult(
            validation_type="compile",
            status="pass",
            output="Build succeeded",
            started_at=datetime.now(timezone.utc),
            finished_at=datetime.now(timezone.utc),
        )
        assert result.status == "pass"
        assert result.passed is True

    def test_failing_result(self):
        """Test creating a failing validation result."""
        result = ValidationResult(
            validation_type="tests",
            status="fail",
            output="2 tests failed",
            exit_code=1,
            error="Test failures detected",
            started_at=datetime.now(timezone.utc),
            finished_at=datetime.now(timezone.utc),
        )
        assert result.status == "fail"
        assert result.passed is False
        assert result.exit_code == 1

    def test_error_result(self):
        """Test creating an error validation result."""
        result = ValidationResult(
            validation_type="compile",
            status="error",
            error="Command not found",
            started_at=datetime.now(timezone.utc),
            finished_at=datetime.now(timezone.utc),
        )
        assert result.status == "error"
        assert result.passed is False


class TestValidateNode:
    """Test the validate_node function."""

    def test_validate_node_with_no_validations(self):
        """Test validate node with no pending validations."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [],
            "validation_results": [],
        }
        result = validate_node(state)
        assert "validation_results" in result
        assert len(result.get("validation_results", [])) == 0

    def test_validate_node_runs_compile_validation(self):
        """Test validate node runs a compile validation."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [
                ValidationConfig(validation_type="compile").__dict__
            ],
            "validation_results": [],
        }
        result = validate_node(state)
        assert "validation_results" in result

    def test_validate_node_returns_state_update(self):
        """Test that validate_node returns a state update dict."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [],
            "validation_results": [],
        }
        result = validate_node(state)
        assert isinstance(result, dict)


class TestDetermineValidationAction:
    """Test the determine_validation_action conditional edge."""

    def test_no_validation_needed(self):
        """Test when no validation is needed."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [],
            "validation_results": [],
        }
        action = determine_validation_action(state)
        assert action == "no_validation"

    def test_validation_needed(self):
        """Test when validation is needed."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [{"validation_type": "compile"}],
            "validation_results": [],
        }
        action = determine_validation_action(state)
        assert action == "validate"

    def test_validation_failed_triggers_intervention(self):
        """Test that failed validation triggers intervention."""
        state: AgentState = {
            "sessions": {},
            "intervention_history": [],
            "current_analysis": None,
            "pending_action": None,
            "pending_validations": [],
            "validation_results": [
                ValidationResult(
                    validation_type="tests",
                    status="fail",
                    output="Tests failed",
                    started_at=datetime.now(timezone.utc),
                    finished_at=datetime.now(timezone.utc),
                ).__dict__
            ],
        }
        action = determine_validation_action(state)
        assert action == "intervene"
