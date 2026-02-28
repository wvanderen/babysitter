defmodule Babysitter.Intervention.SmartTest do
  use ExUnit.Case, async: true

  alias Babysitter.Intervention.Smart
  alias Babysitter.Intervention.Result

  describe "analyze/1 fallback to Dumb" do
    test "returns escalate when max retries exceeded (via Dumb fallback)" do
      session = %{
        id: "test-session-1",
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 3},
        max_retries: 3,
        output_buffer: "",
        validations: []
      }

      result = Smart.analyze(session, use_langgraph: false)

      assert %Result{} = result
      assert result.action == :escalate
      assert result.reason =~ "Max retries"
    end

    test "returns retry on validation failure (via Dumb fallback)" do
      session = %{
        id: "test-session-2",
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0},
        output_buffer: "",
        validations: [%{status: :fail, type: :test, output: "1 failed", exit_code: 1}]
      }

      result = Smart.analyze(session, use_langgraph: false)

      assert result.action == :retry
    end

    test "returns ok for healthy session (via Dumb fallback)" do
      session = %{
        id: "test-session-3",
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0},
        output_buffer: "All good",
        validations: [%{status: :pass, type: :test}]
      }

      result = Smart.analyze(session, use_langgraph: false)

      assert result.action == :ok
    end

    test "handles minimal session fields gracefully" do
      session = %{
        id: "minimal-session",
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0}
      }

      result = Smart.analyze(session, use_langgraph: false)

      assert %Result{} = result
      assert result.action == :ok
    end

    test "returns restart on timeout (via Dumb fallback)" do
      session = %{
        id: "test-session-4",
        current_stage: "stage-1",
        status: :timeout,
        retries: %{"stage-1" => 0}
      }

      result = Smart.analyze(session, use_langgraph: false)

      assert result.action == :restart
    end
  end

  describe "analyze/1 with LangGraph (when unavailable)" do
    test "falls back to Dumb when LangGraph returns error" do
      session = %{
        id: "test-session-5",
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 3},
        max_retries: 3,
        output_buffer: "",
        validations: []
      }

      result = Smart.analyze(session, use_langgraph: true)

      assert %Result{} = result
      assert result.action == :escalate
    end
  end

  describe "build_prompt/1" do
    test "includes session context in prompt" do
      session = %{
        id: "session-123",
        current_stage: "test",
        retries: %{"test" => 2},
        output_buffer: "Test output",
        validations: [%{status: :fail, type: :test}]
      }

      prompt = Smart.build_prompt(session)

      assert is_binary(prompt)
      assert prompt =~ "session-123"
      assert prompt =~ "test"
      assert prompt =~ "Test output"
    end

    test "formats validations in prompt" do
      session = %{
        id: "session-456",
        current_stage: "lint",
        validations: [
          %{status: :fail, type: :lint, output: "Unused variable"},
          %{status: :pass, type: :test}
        ]
      }

      prompt = Smart.build_prompt(session)

      assert prompt =~ "lint"
      assert prompt =~ "Unused variable"
    end

    test "truncates long output buffers" do
      long_output = String.duplicate("Line of output\n", 200)

      session = %{
        id: "session-789",
        current_stage: "build",
        output_buffer: long_output
      }

      prompt = Smart.build_prompt(session)

      assert prompt =~ "truncated"
    end

    test "handles empty output buffer" do
      session = %{
        id: "session-empty",
        current_stage: "init",
        output_buffer: ""
      }

      prompt = Smart.build_prompt(session)

      assert is_binary(prompt)
    end

    test "handles nil output buffer" do
      session = %{
        id: "session-nil",
        current_stage: "init"
      }

      prompt = Smart.build_prompt(session)

      assert is_binary(prompt)
    end

    test "includes retry count" do
      session = %{
        id: "session-retries",
        current_stage: "test",
        retries: %{"test" => 5}
      }

      prompt = Smart.build_prompt(session)

      assert prompt =~ "5"
    end
  end

  describe "parse_response/1" do
    test "parses retry action with context" do
      response = %{
        "action" => "retry",
        "reason" => "Transient error, worth retrying",
        "context" => %{"suggestion" => "Add retry delay"}
      }

      result = Smart.parse_response(response, "stage-1")

      assert result.action == :retry
      assert result.reason =~ "Transient error"
      assert result.context != nil
    end

    test "parses skip action" do
      response = %{
        "action" => "skip",
        "reason" => "Stage not applicable"
      }

      result = Smart.parse_response(response, "optional-stage")

      assert result.action == :skip
      assert result.reason =~ "not applicable"
    end

    test "parses escalate action" do
      response = %{
        "action" => "escalate",
        "reason" => "Requires human decision"
      }

      result = Smart.parse_response(response, "critical-stage")

      assert result.action == :escalate
    end

    test "parses ok action" do
      response = %{
        "action" => "ok"
      }

      result = Smart.parse_response(response, "stage-1")

      assert result.action == :ok
    end

    test "handles invalid response by escalating" do
      response = %{"invalid" => "data"}

      result = Smart.parse_response(response, "stage-1")

      assert result.action == :escalate
      assert result.reason =~ "Unknown action"
    end

    test "handles unknown action by escalating" do
      response = %{"action" => "unknown_action"}

      result = Smart.parse_response(response, "stage-1")

      assert result.action == :escalate
    end

    test "handles nil response" do
      result = Smart.parse_response(nil, "stage-1")

      assert result.action == :escalate
      assert result.reason =~ "parse"
    end

    test "handles non-map response" do
      result = Smart.parse_response("invalid", "stage-1")

      assert result.action == :escalate
      assert result.reason =~ "Invalid response"
    end

    test "includes stage_id in result" do
      response = %{"action" => "retry", "reason" => "test"}

      result = Smart.parse_response(response, "my-stage")

      assert result.stage_id == "my-stage"
    end
  end

  describe "format_validations/1" do
    test "formats empty validations" do
      assert Smart.format_validations([]) =~ "No validations"
    end

    test "formats nil validations" do
      assert Smart.format_validations(nil) =~ "No validations"
    end

    test "formats passing validation" do
      validations = [%{status: :pass, type: :test, output: "All tests pass"}]

      formatted = Smart.format_validations(validations)

      assert formatted =~ "test"
      assert formatted =~ "pass"
      assert formatted =~ "✓"
    end

    test "formats failing validation" do
      validations = [%{status: :fail, type: :lint, output: "3 warnings"}]

      formatted = Smart.format_validations(validations)

      assert formatted =~ "lint"
      assert formatted =~ "fail"
      assert formatted =~ "✗"
    end

    test "formats multiple validations" do
      validations = [
        %{status: :pass, type: :test, output: "All tests pass"},
        %{status: :fail, type: :lint, output: "3 warnings"}
      ]

      formatted = Smart.format_validations(validations)

      assert formatted =~ "test"
      assert formatted =~ "lint"
    end

    test "truncates long validation output" do
      long_output = String.duplicate("x", 300)

      validations = [
        %{status: :fail, type: :build, output: long_output}
      ]

      formatted = Smart.format_validations(validations)

      assert String.length(formatted) < 500
    end

    test "handles validation without output" do
      validations = [%{status: :pass, type: :test}]

      formatted = Smart.format_validations(validations)

      assert formatted =~ "test"
    end
  end
end
