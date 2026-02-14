defmodule Babysitter.StageExecutorTest do
  use ExUnit.Case, async: false

  alias Babysitter.{SessionManager, Stage, StageExecutor, Validation}

  setup do
    session_id = "executor-test-#{:rand.uniform(1_000_000)}"
    {:ok, _} = SessionManager.create_session(session_id)

    on_exit(fn ->
      SessionManager.destroy_session(session_id)
    end)

    {:ok, session_id: session_id}
  end

  describe "execute/3" do
    test "executes agent stage in tmux session", %{session_id: session_id} do
      stage = Stage.agent(:test, "echo 'Hello World'")

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.stage_id == :test
      assert result.session_id == session_id
      assert result.status == :success
      assert result.output =~ "Hello World"
    end

    test "returns error for non-existent session" do
      stage = Stage.agent(:test, "echo test")

      assert {:error, {:session_not_found, _}} =
               StageExecutor.execute(stage, "nonexistent-#{:rand.uniform(1_000_000)}")
    end

    test "executes action stage in tmux session", %{session_id: session_id} do
      stage = Stage.action(:build, "echo 'Building'")

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.stage_id == :build
      assert result.session_id == session_id
      assert result.status == :success
      assert result.output =~ "Building"
      assert result.exit_code == 0
    end

    test "action stage captures non-zero exit code", %{session_id: session_id} do
      stage = Stage.action(:fail_test, "exit 42")

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.status == :failure
      assert result.exit_code == 42
    end

    test "action stage with environment variables", %{session_id: session_id} do
      stage = Stage.action(:env_test, "echo $MY_VAR")
      opts = [env: [MY_VAR: "hello_from_env"], max_wait: 5_000]

      assert {:ok, result} = StageExecutor.execute(stage, session_id, opts)
      assert result.status == :success
      assert result.output =~ "hello_from_env"
    end

    test "returns error for stage without prompt", %{session_id: session_id} do
      stage = %Stage{id: :broken, type: :agent, prompt: nil}

      assert {:error, :no_prompt_defined} =
               StageExecutor.execute(stage, session_id)
    end

    test "returns error for empty prompt", %{session_id: session_id} do
      stage = %Stage{id: :empty, type: :agent, prompt: ""}

      assert {:error, :empty_prompt} =
               StageExecutor.execute(stage, session_id)
    end

    test "returns error for action without command", %{session_id: session_id} do
      stage = %Stage{id: :no_cmd, type: :action, command: nil}

      assert {:error, :no_command_defined} =
               StageExecutor.execute(stage, session_id)
    end

    test "returns error for action with empty command", %{session_id: session_id} do
      stage = %Stage{id: :empty_cmd, type: :action, command: ""}

      assert {:error, :empty_command} =
               StageExecutor.execute(stage, session_id)
    end
  end

  describe "execute_and_wait/3" do
    test "executes and waits for completion", %{session_id: session_id} do
      stage = Stage.agent(:wait_test, "echo 'Done'")
      opts = [poll_interval: 100, max_wait: 5_000]

      assert {:ok, result} = StageExecutor.execute_and_wait(stage, session_id, opts)
      assert result.status == :success
      assert result.output =~ "Done"
    end

    test "times out after max_wait", %{session_id: session_id} do
      stage = Stage.agent(:timeout_test, "sleep 10")
      completion_check = fn _output -> false end
      opts = [poll_interval: 50, max_wait: 200, completion_check: completion_check]

      assert {:ok, result} = StageExecutor.execute_and_wait(stage, session_id, opts)
      assert result.status == :timeout
      assert result.error =~ "timed out"
    end

    test "uses completion check function", %{session_id: session_id} do
      stage = Stage.agent(:check_test, "echo 'MARKER_COMPLETE'")
      completion_check = &String.contains?(&1, "MARKER_COMPLETE")
      opts = [poll_interval: 100, max_wait: 5_000, completion_check: completion_check]

      assert {:ok, result} = StageExecutor.execute_and_wait(stage, session_id, opts)
      assert result.status == :success
    end
  end

  describe "validate_result/2" do
    test "passes when all validations pass" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :success,
        output: "Success! Build completed",
        exit_code: 0
      }

      validations = [
        Validation.output_contains("Success"),
        Validation.exit_code(0)
      ]

      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "returns errors when validations fail" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :failure,
        output: "Error occurred",
        exit_code: 1
      }

      validations = [
        Validation.output_contains("Success"),
        Validation.exit_code(0)
      ]

      assert {:error, errors} = StageExecutor.validate_result(result, validations)
      assert length(errors) == 2
    end

    test "handles empty validation list" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :success,
        output: "Any output",
        exit_code: 0
      }

      assert :ok = StageExecutor.validate_result(result, [])
    end
  end

  describe "run_validations/3 integration" do
    test "action stage with passing validations remains success", %{session_id: session_id} do
      stage =
        Stage.action(:validated, "echo 'Build succeeded'",
          validations: [
            Validation.output_contains("succeeded"),
            Validation.exit_code(0)
          ]
        )

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.status == :success
      assert result.validation_errors == nil
    end

    test "action stage with failing validations becomes failure", %{session_id: session_id} do
      stage =
        Stage.action(:validated, "echo 'Build done'",
          validations: [
            Validation.output_contains("succeeded")
          ]
        )

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.status == :failure
      assert result.validation_errors != nil
      assert length(result.validation_errors) == 1
    end

    test "validation results are stored in session", %{session_id: session_id} do
      stage =
        Stage.action(:store_test, "echo 'output'",
          validations: [
            Validation.output_contains("missing")
          ]
        )

      {:ok, _result} = StageExecutor.execute(stage, session_id)

      {:ok, session} = Babysitter.Session.get_state(session_id)
      assert Map.has_key?(session.validation_results, :store_test)
    end

    test "agent stage with passing validations remains success", %{session_id: session_id} do
      stage =
        Stage.agent(:agent_validated, "echo 'Task complete'",
          validations: [
            Validation.output_contains("complete")
          ]
        )

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.status == :success
      assert result.validation_errors == nil
    end

    test "agent stage with failing validations becomes failure", %{session_id: session_id} do
      stage =
        Stage.agent(:agent_fail, "echo 'done'",
          validations: [
            Validation.output_contains("SUCCESS_MARKER")
          ]
        )

      assert {:ok, result} = StageExecutor.execute(stage, session_id)
      assert result.status == :failure
      assert result.validation_errors != nil
    end
  end

  describe "Result" do
    test "success?/1 returns true for success status" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :success
      }

      assert StageExecutor.Result.success?(result)
    end

    test "success?/1 returns false for failure status" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :failure
      }

      refute StageExecutor.Result.success?(result)
    end

    test "timeout?/1 returns true for timeout status" do
      result = %StageExecutor.Result{
        stage_id: :test,
        session_id: "test",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        status: :timeout
      }

      assert StageExecutor.Result.timeout?(result)
    end
  end
end
