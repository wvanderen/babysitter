defmodule Babysitter.RetryHandlerTest do
  use ExUnit.Case, async: true

  alias Babysitter.{RetryHandler, Stage, StageContext, StageExecutor.Result}
  alias Babysitter.Intervention.Result, as: InterventionResult

  describe "build_retry_prompt/3" do
    setup do
      stage = %Stage{id: :test_stage, type: :agent, prompt: "Write a function that adds two numbers"}
      {:ok, stage: stage}
    end

    test "builds prompt with error context for failed result", %{stage: stage} do
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        error: "Compilation error", output: "def add(a, b), do: a +", exit_code: 1,
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result)
      assert String.contains?(prompt, "Compilation error")
      assert String.contains?(prompt, "Write a function that adds two numbers")
      assert String.contains?(prompt, "Previous Output")
    end

    test "builds prompt with validation errors", %{stage: stage} do
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        output: "output", exit_code: 0, validation_errors: ["Missing test file", "Wrong function name"],
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result)
      assert String.contains?(prompt, "Validation Errors")
      assert String.contains?(prompt, "Missing test file")
    end

    test "truncates long output", %{stage: stage} do
      long_output = String.duplicate("x", 5000)
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        error: "Error", output: long_output, exit_code: 1,
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result, max_output_length: 100)
      assert String.length(prompt) < 6000
      assert String.contains?(prompt, "last 100")
    end

    test "excludes previous output when option is false", %{stage: stage} do
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        error: "Error", output: "Some output", exit_code: 1,
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result, include_previous_output: false)
      refute String.contains?(prompt, "Previous Output")
    end

    test "handles timeout status", %{stage: stage} do
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :timeout,
        output: "Partial output", exit_code: nil, error: "Timed out",
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result)
      assert String.contains?(prompt, "timed out") or String.contains?(prompt, "Timed out")
    end

    test "uses custom template when provided", %{stage: stage} do
      custom_template = "Retry attempt {{retry.retry_count}}!\nError: {{retry.error_message}}\nTask: {{retry.original_prompt}}"
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        error: "Test error", output: "", exit_code: 1,
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      prompt = RetryHandler.build_retry_prompt(stage, result, template: custom_template, retry_count: 2)
      assert String.contains?(prompt, "Retry attempt 2")
      assert String.contains?(prompt, "Test error")
    end
  end

  describe "build_retry_prompt_from_intervention/4" do
    test "builds prompt from intervention result" do
      stage = %Stage{id: :test_stage, type: :agent, prompt: "Original task"}
      result = %Result{
        stage_id: :test_stage, session_id: "session-1", status: :failure,
        output: "Bad output", exit_code: 1,
        started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()
      }
      intervention = InterventionResult.retry("Validation failed", context: %{validation_type: :custom, error_output: "Validation output", exit_code: 1})
      prompt = RetryHandler.build_retry_prompt_from_intervention(stage, result, intervention)
      assert String.contains?(prompt, "Validation failed")
      assert String.contains?(prompt, "Original task")
    end
  end

  describe "should_retry?/2" do
    test "returns false for successful result" do
      result = %Result{stage_id: :test, session_id: "s1", status: :success, output: "Done", exit_code: 0, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      refute RetryHandler.should_retry?(result, max_retries: 3)
    end

    test "returns true for failed result with retries remaining" do
      result = %Result{stage_id: :test, session_id: "s1", status: :failure, error: "Error", exit_code: 1, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      assert RetryHandler.should_retry?(result, max_retries: 3, retry_count: 1)
    end

    test "returns false when max retries exceeded" do
      result = %Result{stage_id: :test, session_id: "s1", status: :failure, error: "Error", exit_code: 1, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      refute RetryHandler.should_retry?(result, max_retries: 3, retry_count: 3)
    end

    test "returns true for timeout with retries remaining" do
      result = %Result{stage_id: :test, session_id: "s1", status: :timeout, error: "Timed out", exit_code: nil, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      assert RetryHandler.should_retry?(result, max_retries: 3, retry_count: 0)
    end

    test "respects recoverable option" do
      result = %Result{stage_id: :test, session_id: "s1", status: :failure, error: "Error", exit_code: 1, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      refute RetryHandler.should_retry?(result, recoverable: false)
    end
  end

  describe "record_retry/3" do
    test "records retry in stage context" do
      context = StageContext.new()
      result = %Result{stage_id: :build, session_id: "s1", status: :failure, error: "Build failed", exit_code: 1, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      updated = RetryHandler.record_retry(context, result, retry_count: 1)
      assert StageContext.has_errors?(updated)
      assert StageContext.get_variable(updated, :retry_count) == 1
      assert StageContext.get_variable(updated, :last_retry_error) =~ "Build failed"
    end
  end

  describe "format_validation_errors/1" do
    test "formats list of errors with bullets" do
      assert RetryHandler.format_validation_errors(["Error 1", "Error 2", "Error 3"]) == "- Error 1\n- Error 2\n- Error 3"
    end
    test "returns empty string for empty list", do: assert(RetryHandler.format_validation_errors([]) == "")
    test "formats single string error", do: assert(RetryHandler.format_validation_errors("Single error") == "- Single error")
    test "returns empty string for nil", do: assert(RetryHandler.format_validation_errors(nil) == "")
  end

  describe "truncate_output/2" do
    test "returns short output unchanged" do
      assert RetryHandler.truncate_output("Short output", max_length: 100) == "Short output"
    end
    test "truncates long output keeping the end" do
      output = String.duplicate("a", 100)
      truncated = RetryHandler.truncate_output(output, max_length: 20)
      assert String.length(truncated) == 20
      assert String.starts_with?(truncated, "... ")
    end
    test "handles nil output", do: assert(RetryHandler.truncate_output(nil) == "")
    test "joins list output", do: assert(RetryHandler.truncate_output(["Line 1", "Line 2"], max_length: 100) == "Line 1\nLine 2")
  end

  describe "build_retry_opts/3" do
    test "includes retry environment variables" do
      context = StageContext.new(issue_id: "td-123")
      result = %Result{stage_id: :test, session_id: "s1", status: :failure, error: "Test error", exit_code: 1, started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      opts = RetryHandler.build_retry_opts(context, result, retry_count: 2)
      assert Keyword.get(opts, :env) != nil
      env = Keyword.get(opts, :env)
      assert {"RETRY_COUNT", "2"} in env
      assert {"RETRY_ERROR", "Test error"} in env
      assert {"RETRY_EXIT_CODE", "1"} in env
    end

    test "includes validation errors when present" do
      context = StageContext.new()
      result = %Result{stage_id: :test, session_id: "s1", status: :failure, exit_code: 0, validation_errors: ["Error 1", "Error 2"], started_at: DateTime.utc_now(), finished_at: DateTime.utc_now()}
      opts = RetryHandler.build_retry_opts(context, result)
      env = Keyword.get(opts, :env)
      assert {"RETRY_VALIDATION_ERRORS", "Error 1; Error 2"} in env
    end
  end
end
