defmodule Babysitter.InterventionTest do
  use ExUnit.Case, async: true

  alias Babysitter.Intervention
  alias Babysitter.Intervention.Result
  alias Babysitter.Intervention.Dumb

  describe "Result" do
    test "ok/0 returns ok result" do
      result = Result.ok()
      assert result.action == :ok
      assert result.reason == nil
    end

    test "retry/2 returns retry result" do
      result = Result.retry("Test reason", context: %{foo: "bar"})
      assert result.action == :retry
      assert result.reason == "Test reason"
      assert result.context == %{foo: "bar"}
    end

    test "restart/2 returns restart result" do
      result = Result.restart("Restart reason")
      assert result.action == :restart
      assert result.reason == "Restart reason"
    end

    test "escalate/2 returns escalate result" do
      result = Result.escalate("Escalate reason", stage_id: "stage-1")
      assert result.action == :escalate
      assert result.reason == "Escalate reason"
      assert result.stage_id == "stage-1"
    end

    test "skip/2 returns skip result" do
      result = Result.skip("Skip reason")
      assert result.action == :skip
    end

    test "needs_action?/1 returns correct boolean" do
      refute Result.needs_action?(Result.ok())
      assert Result.needs_action?(Result.retry("test"))
      assert Result.needs_action?(Result.escalate("test"))
    end
  end

  describe "Dumb.check/1" do
    test "returns ok for healthy session" do
      session = %{
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0}
      }

      result = Dumb.check(session)
      assert result.action == :ok
    end

    test "escalates when max retries exceeded" do
      session = %{
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 3},
        max_retries: 3
      }

      result = Dumb.check(session)
      assert result.action == :escalate
      assert result.reason =~ "Max retries"
    end

    test "restarts on timeout" do
      session = %{
        current_stage: "stage-1",
        status: :timeout,
        retries: %{"stage-1" => 0}
      }

      result = Dumb.check(session)
      assert result.action == :restart
      assert result.reason =~ "timed out"
    end

    test "retries on validation failure" do
      session = %{
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0},
        validations: [
          %{status: :fail, type: :test, output: "1 test failed", exit_code: 1}
        ]
      }

      result = Dumb.check(session)
      assert result.action == :retry
      assert result.reason =~ "Validation failed"
    end

    test "escalates when stuck too long" do
      stuck_time = DateTime.utc_now() |> DateTime.add(-15, :minute)

      session = %{
        current_stage: "stage-1",
        status: :running,
        retries: %{"stage-1" => 0},
        last_activity: stuck_time,
        stuck_threshold_minutes: 10
      }

      result = Dumb.check(session)
      assert result.action == :escalate
      assert result.reason =~ "No progress"
    end
  end

  describe "Dumb.check_max_retries/1" do
    test "returns ok when under limit" do
      session = %{current_stage: "s1", retries: %{"s1" => 1}, max_retries: 3}
      assert Dumb.check_max_retries(session).action == :ok
    end

    test "escalates at limit" do
      session = %{current_stage: "s1", retries: %{"s1" => 3}, max_retries: 3}
      result = Dumb.check_max_retries(session)
      assert result.action == :escalate
    end

    test "escalates over limit" do
      session = %{current_stage: "s1", retries: %{"s1" => 5}, max_retries: 3}
      result = Dumb.check_max_retries(session)
      assert result.action == :escalate
    end
  end

  describe "Dumb.check_timeout/1" do
    test "returns ok for non-timeout status" do
      session = %{status: :running}
      assert Dumb.check_timeout(session).action == :ok
    end

    test "restarts for timeout status" do
      session = %{status: :timeout, current_stage: "s1"}
      result = Dumb.check_timeout(session)
      assert result.action == :restart
    end
  end

  describe "Dumb.check_validation_failure/1" do
    test "returns ok when no validations" do
      session = %{validations: nil}
      assert Dumb.check_validation_failure(session).action == :ok
    end

    test "returns ok for passing validation" do
      session = %{validations: [%{status: :pass, type: :test}]}
      assert Dumb.check_validation_failure(session).action == :ok
    end

    test "retries for failed validation" do
      session = %{
        current_stage: "s1",
        validations: [%{status: :fail, type: :compile, output: "error", exit_code: 1}]
      }

      result = Dumb.check_validation_failure(session)
      assert result.action == :retry
      assert result.context.validation_type == :compile
    end

    test "retries for error validation" do
      session = %{
        current_stage: "s1",
        validations: [%{status: :error, type: :lint, error: "timeout"}]
      }

      result = Dumb.check_validation_failure(session)
      assert result.action == :retry
    end
  end

  describe "Dumb.check_stuck/1" do
    test "returns ok for recent activity" do
      session = %{
        last_activity: DateTime.utc_now() |> DateTime.add(-5, :minute),
        stuck_threshold_minutes: 10
      }

      assert Dumb.check_stuck(session).action == :ok
    end

    test "escalates for old activity" do
      session = %{
        current_stage: "s1",
        last_activity: DateTime.utc_now() |> DateTime.add(-15, :minute),
        stuck_threshold_minutes: 10
      }

      result = Dumb.check_stuck(session)
      assert result.action == :escalate
    end
  end

  describe "Intervention.check/2" do
    test "delegates to Dumb by default" do
      session = %{current_stage: "s1", status: :running, retries: %{"s1" => 0}}
      result = Intervention.check(session, :dumb)
      assert result.action == :ok
    end

    test "delegates to Smart when mode is smart" do
      session = %{
        id: "smart-session",
        current_stage: "s1",
        status: :running,
        retries: %{"s1" => 0}
      }

      result = Intervention.check(session, :smart)

      assert %Result{} = result
      assert result.action in [:ok, :retry, :restart, :escalate, :skip]
    end

    test "hybrid mode uses Smart after Dumb finds non-ok result" do
      session = %{
        id: "hybrid-session",
        current_stage: "s1",
        status: :running,
        retries: %{"s1" => 2},
        validations: [%{status: :fail, type: :test, output: "err", exit_code: 1}]
      }

      result = Intervention.check(session, :hybrid)

      assert %Result{} = result
    end
  end
end
