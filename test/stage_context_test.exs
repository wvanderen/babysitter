defmodule Babysitter.StageContextTest do
  use ExUnit.Case, async: true

  alias Babysitter.{StageContext, StageExecutor.Result}

  describe "new/1" do
    test "creates empty context" do
      context = StageContext.new()
      assert context.issue_id == nil
      assert context.variables == %{}
      assert context.error_context == []
      assert context.stage_history == []
    end

    test "creates context with options" do
      context =
        StageContext.new(
          issue_id: "td-123",
          workflow_id: "wf-456",
          session_id: "sess-789",
          variables: %{branch: "main"}
        )

      assert context.issue_id == "td-123"
      assert context.workflow_id == "wf-456"
      assert context.session_id == "sess-789"
      assert context.variables == %{branch: "main"}
    end
  end

  describe "put_variable/3 and get_variable/3" do
    test "sets and gets variable" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      assert StageContext.get_variable(context, :branch) == "main"
    end

    test "handles string keys" do
      context = StageContext.new()
      context = StageContext.put_variable(context, "branch", "main")
      assert StageContext.get_variable(context, :branch) == "main"
      assert StageContext.get_variable(context, "branch") == "main"
    end

    test "returns default for missing variable" do
      context = StageContext.new()
      assert StageContext.get_variable(context, :missing, "default") == "default"
    end

    test "overwrites existing variable" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      context = StageContext.put_variable(context, :branch, "develop")
      assert StageContext.get_variable(context, :branch) == "develop"
    end
  end

  describe "put_variables/2" do
    test "sets multiple variables at once" do
      context = StageContext.new()
      context = StageContext.put_variables(context, %{branch: "main", commit: "abc123"})
      assert StageContext.get_variable(context, :branch) == "main"
      assert StageContext.get_variable(context, :commit) == "abc123"
    end

    test "merges with existing variables" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :existing, "value")
      context = StageContext.put_variables(context, %{branch: "main"})
      assert StageContext.get_variable(context, :existing) == "value"
      assert StageContext.get_variable(context, :branch) == "main"
    end
  end

  describe "get_all_variables/1" do
    test "returns all variables as map" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      context = StageContext.put_variable(context, :commit, "abc123")
      assert StageContext.get_all_variables(context) == %{branch: "main", commit: "abc123"}
    end
  end

  describe "delete_variable/2" do
    test "removes variable" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      context = StageContext.delete_variable(context, :branch)
      assert StageContext.get_variable(context, :branch) == nil
    end
  end

  describe "extract_from_output/4" do
    test "extracts value using regex with capture group" do
      context = StageContext.new()
      output = "Current branch: main"
      context = StageContext.extract_from_output(context, :branch, ~r/branch:\s*(\S+)/, output)
      assert StageContext.get_variable(context, :branch) == "main"
    end

    test "extracts value using regex without capture group" do
      context = StageContext.new()
      output = "Status: OK"
      context = StageContext.extract_from_output(context, :status, ~r/Status: OK/, output)
      assert StageContext.get_variable(context, :status) == "Status: OK"
    end

    test "extracts value using string pattern" do
      context = StageContext.new()
      output = "Build completed successfully"
      context = StageContext.extract_from_output(context, :build_status, "successfully", output)
      assert StageContext.get_variable(context, :build_status) == "successfully"
    end

    test "extracts value using function" do
      context = StageContext.new()
      output = "Result: 42"

      extractor = fn text ->
        case Regex.run(~r/Result: (\d+)/, text) do
          [_, num] -> {:ok, String.to_integer(num)}
          _ -> :not_found
        end
      end

      context = StageContext.extract_from_output(context, :result, extractor, output)
      assert StageContext.get_variable(context, :result) == 42
    end

    test "does not set variable if pattern not found" do
      context = StageContext.new()
      output = "Some random output"
      context = StageContext.extract_from_output(context, :branch, ~r/branch:\s*(\S+)/, output)
      assert StageContext.get_variable(context, :branch) == nil
    end

    test "handles empty output" do
      context = StageContext.new()
      context = StageContext.extract_from_output(context, :branch, ~r/branch:\s*(\S+)/, "")
      assert StageContext.get_variable(context, :branch) == nil
    end
  end

  describe "extract_multiple/3" do
    test "extracts multiple values at once" do
      context = StageContext.new()
      output = "Branch: main Commit: abc123 Status: passing"

      patterns = %{
        branch: ~r/Branch:\s*(\S+)/,
        commit: ~r/Commit:\s*(\S+)/,
        status: ~r/Status:\s*(\S+)/
      }

      context = StageContext.extract_multiple(context, patterns, output)
      assert StageContext.get_variable(context, :branch) == "main"
      assert StageContext.get_variable(context, :commit) == "abc123"
      assert StageContext.get_variable(context, :status) == "passing"
    end
  end

  describe "record_stage_result/2" do
    test "records stage result in history" do
      context = StageContext.new()

      result = %Result{
        stage_id: :analyze,
        session_id: "sess-1",
        status: :success,
        output: "Analysis complete",
        exit_code: 0,
        started_at: ~U[2024-01-01 00:00:00Z],
        finished_at: ~U[2024-01-01 00:01:00Z]
      }

      context = StageContext.record_stage_result(context, result)

      history = context.stage_history
      assert length(history) == 1
      assert hd(history).stage_id == :analyze
      assert hd(history).status == :success
      assert hd(history).output == "Analysis complete"
    end

    test "appends to history" do
      context = StageContext.new()

      r1 = %Result{
        stage_id: :analyze,
        session_id: "sess-1",
        started_at: ~U[2024-01-01 00:00:00Z],
        finished_at: ~U[2024-01-01 00:01:00Z]
      }

      r2 = %Result{
        stage_id: :build,
        session_id: "sess-1",
        started_at: ~U[2024-01-01 00:01:00Z],
        finished_at: ~U[2024-01-01 00:02:00Z]
      }

      context = StageContext.record_stage_result(context, r1)
      context = StageContext.record_stage_result(context, r2)

      assert length(context.stage_history) == 2
      assert Enum.at(context.stage_history, 0).stage_id == :analyze
      assert Enum.at(context.stage_history, 1).stage_id == :build
    end
  end

  describe "record_error/3" do
    test "records error in context" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Build failed", :execution)

      errors = context.error_context
      assert length(errors) == 1
      assert hd(errors).stage_id == :build
      assert hd(errors).message == "Build failed"
      assert hd(errors).type == :execution
    end

    test "defaults error type to :execution" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Build failed")
      assert hd(context.error_context).type == :execution
    end
  end

  describe "has_errors?/1" do
    test "returns false for empty context" do
      context = StageContext.new()
      refute StageContext.has_errors?(context)
    end

    test "returns true when errors present" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Failed", :execution)
      assert StageContext.has_errors?(context)
    end
  end

  describe "get_errors/2" do
    test "returns errors for specific stage" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Error 1", :execution)
      context = StageContext.record_error(context, :test, "Error 2", :execution)
      context = StageContext.record_error(context, :build, "Error 3", :execution)

      build_errors = StageContext.get_errors(context, :build)
      assert length(build_errors) == 2
    end

    test "returns empty list for stage with no errors" do
      context = StageContext.new()
      assert StageContext.get_errors(context, :nonexistent) == []
    end
  end

  describe "get_all_errors/1" do
    test "returns all errors" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Error 1", :execution)
      context = StageContext.record_error(context, :test, "Error 2", :execution)

      errors = StageContext.get_all_errors(context)
      assert length(errors) == 2
    end
  end

  describe "clear_errors/1" do
    test "removes all errors" do
      context = StageContext.new()
      context = StageContext.record_error(context, :build, "Failed", :execution)
      context = StageContext.clear_errors(context)
      assert context.error_context == []
    end
  end

  describe "get_last_result/1" do
    test "returns nil for empty history" do
      context = StageContext.new()
      assert StageContext.get_last_result(context) == nil
    end

    test "returns last result" do
      context = StageContext.new()

      r1 = %Result{
        stage_id: :first,
        session_id: "s",
        started_at: ~U[2024-01-01 00:00:00Z],
        finished_at: ~U[2024-01-01 00:01:00Z]
      }

      r2 = %Result{
        stage_id: :second,
        session_id: "s",
        started_at: ~U[2024-01-01 00:01:00Z],
        finished_at: ~U[2024-01-01 00:02:00Z]
      }

      context = StageContext.record_stage_result(context, r1)
      context = StageContext.record_stage_result(context, r2)

      last = StageContext.get_last_result(context)
      assert last.stage_id == :second
    end
  end

  describe "get_result/2" do
    test "returns result for specific stage" do
      context = StageContext.new()

      r1 = %Result{
        stage_id: :analyze,
        session_id: "s",
        output: "output1",
        started_at: ~U[2024-01-01 00:00:00Z],
        finished_at: ~U[2024-01-01 00:01:00Z]
      }

      r2 = %Result{
        stage_id: :build,
        session_id: "s",
        output: "output2",
        started_at: ~U[2024-01-01 00:01:00Z],
        finished_at: ~U[2024-01-01 00:02:00Z]
      }

      context = StageContext.record_stage_result(context, r1)
      context = StageContext.record_stage_result(context, r2)

      result = StageContext.get_result(context, :build)
      assert result.output == "output2"
    end

    test "returns nil for nonexistent stage" do
      context = StageContext.new()
      assert StageContext.get_result(context, :nonexistent) == nil
    end
  end

  describe "get_stage_output/2" do
    test "returns output for specific stage" do
      context = StageContext.new()

      result = %Result{
        stage_id: :analyze,
        session_id: "s",
        output: "Analysis output",
        started_at: ~U[2024-01-01 00:00:00Z],
        finished_at: ~U[2024-01-01 00:01:00Z]
      }

      context = StageContext.record_stage_result(context, result)

      assert StageContext.get_stage_output(context, :analyze) == "Analysis output"
    end

    test "returns nil for nonexistent stage" do
      context = StageContext.new()
      assert StageContext.get_stage_output(context, :nonexistent) == nil
    end
  end

  describe "to_template_context/1" do
    test "converts context to template-friendly map" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      context = StageContext.record_error(context, :build, "Failed", :execution)

      template_ctx = StageContext.to_template_context(context)

      assert template_ctx.variables == %{branch: "main"}
      assert template_ctx.has_errors == true
      assert length(template_ctx.errors) == 1
    end
  end

  describe "to_execution_opts/2" do
    test "creates execution options with context" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")
      context = StageContext.put_variable(context, :commit_sha, "abc123")

      opts = StageContext.to_execution_opts(context, max_wait: 60_000)

      assert Keyword.get(opts, :context) == context
      assert Keyword.get(opts, :max_wait) == 60_000

      env = Keyword.get(opts, :env, [])
      assert {"BRANCH", "main"} in env
      assert {"COMMIT_SHA", "abc123"} in env
    end

    test "merges with existing env vars" do
      context = StageContext.new()
      context = StageContext.put_variable(context, :branch, "main")

      opts = StageContext.to_execution_opts(context, env: [{"EXISTING", "value"}])

      env = Keyword.get(opts, :env, [])
      assert {"EXISTING", "value"} in env
      assert {"BRANCH", "main"} in env
    end
  end

  describe "merge/2" do
    test "merges two contexts" do
      left = StageContext.new(issue_id: "td-123")
      left = StageContext.put_variable(left, :a, 1)
      left = StageContext.put_variable(left, :shared, "left")

      right = StageContext.new(workflow_id: "wf-456")
      right = StageContext.put_variable(right, :b, 2)
      right = StageContext.put_variable(right, :shared, "right")

      merged = StageContext.merge(left, right)

      assert merged.issue_id == "td-123"
      assert merged.workflow_id == "wf-456"
      assert StageContext.get_variable(merged, :a) == 1
      assert StageContext.get_variable(merged, :b) == 2
      assert StageContext.get_variable(merged, :shared) == "right"
    end
  end

  describe "child/2" do
    test "creates child context inheriting from parent" do
      parent = StageContext.new(issue_id: "td-123", workflow_id: "wf-456")
      parent = StageContext.put_variable(parent, :branch, "main")
      parent = StageContext.record_error(parent, :build, "Failed", :execution)

      child = StageContext.child(parent, metadata: %{retry: 1})

      assert child.issue_id == "td-123"
      assert child.workflow_id == "wf-456"
      assert StageContext.get_variable(child, :branch) == "main"
      assert child.metadata == %{retry: 1}
      assert child.stage_history == []
      assert child.error_context == parent.error_context
    end

    test "child can override parent values" do
      parent = StageContext.new(issue_id: "td-123")
      parent = StageContext.put_variable(parent, :branch, "main")

      child = StageContext.child(parent, issue_id: "td-456", variables: %{branch: "develop"})

      assert child.issue_id == "td-456"
      assert StageContext.get_variable(child, :branch) == "develop"
    end
  end
end
