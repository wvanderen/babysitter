defmodule Babysitter.TransitionEngineTest do
  use ExUnit.Case, async: true

  alias Babysitter.{Stage, Transition, TransitionEngine, StageExecutor.Result}

  describe "next_stage/2 with shortcuts" do
    test "returns on_success for successful result" do
      stage = Stage.agent(:impl, "prompt", on_success: :review)
      result = build_result(status: :success)

      assert {:ok, :review} = TransitionEngine.next_stage(stage, result)
    end

    test "returns on_failure for failed result" do
      stage = Stage.agent(:impl, "prompt", on_success: :review, on_failure: :retry)
      result = build_result(status: :failure)

      assert {:ok, :retry} = TransitionEngine.next_stage(stage, result)
    end

    test "returns on_timeout for timeout result" do
      stage =
        Stage.agent(:impl, "prompt",
          on_success: :review,
          on_failure: :retry,
          on_timeout: :escalate
        )

      result = build_result(status: :timeout)

      assert {:ok, :escalate} = TransitionEngine.next_stage(stage, result)
    end

    test "falls back to on_failure when on_timeout not defined" do
      stage = Stage.agent(:impl, "prompt", on_success: :review, on_failure: :retry)
      result = build_result(status: :timeout)

      assert {:ok, :retry} = TransitionEngine.next_stage(stage, result)
    end

    test "falls back to on_success when on_failure not defined" do
      stage = Stage.agent(:impl, "prompt", on_success: :complete)
      result = build_result(status: :failure)

      assert {:ok, :complete} = TransitionEngine.next_stage(stage, result)
    end

    test "returns error when no transition defined" do
      stage = Stage.agent(:impl, "prompt")
      result = build_result(status: :success)

      assert {:error, :no_transition_defined} = TransitionEngine.next_stage(stage, result)
    end
  end

  describe "next_stage/2 with explicit transitions" do
    test "evaluates transitions in priority order" do
      stage =
        Stage.decision(:check, [
          Transition.on_success(:review),
          Transition.always(:fallback)
        ])

      result = build_result(status: :success)

      assert {:ok, :review} = TransitionEngine.next_stage(stage, result)
    end

    test "matches :always condition" do
      stage =
        Stage.decision(:check, [
          Transition.always(:always_stage)
        ])

      result = build_result(status: :failure)

      assert {:ok, :always_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches :success condition" do
      stage =
        Stage.decision(:check, [
          Transition.on_failure(:fail_stage),
          Transition.on_success(:success_stage)
        ])

      result = build_result(status: :success)

      assert {:ok, :success_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches :failure condition" do
      stage =
        Stage.decision(:check, [
          Transition.on_success(:success_stage),
          Transition.on_failure(:fail_stage)
        ])

      result = build_result(status: :failure)

      assert {:ok, :fail_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches :timeout condition" do
      stage =
        Stage.decision(:check, [
          Transition.on_timeout(:timeout_stage)
        ])

      result = build_result(status: :timeout)

      assert {:ok, :timeout_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches output_contains condition" do
      stage =
        Stage.decision(:check, [
          Transition.when_output_contains(:found_stage, "DONE")
        ])

      result = build_result(status: :success, output: "Work complete\nDONE\n")

      assert {:ok, :found_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches output_matches regex condition" do
      stage =
        Stage.decision(:check, [
          Transition.when_output_matches(:error_stage, ~r/Error: .+/)
        ])

      result =
        build_result(status: :success, output: "Something happened\nError: file not found\n")

      assert {:ok, :error_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches exit_code condition" do
      stage =
        Stage.decision(:check, [
          Transition.when_exit_code(:code_42_stage, 42)
        ])

      result = build_result(status: :failure, exit_code: 42)

      assert {:ok, :code_42_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "matches custom function condition" do
      custom_fn = fn output, _exit_code ->
        String.contains?(output, "RETRY") and String.contains?(output, "rate_limit")
      end

      stage =
        Stage.decision(:check, [
          Transition.when_custom(:retry_stage, custom_fn)
        ])

      result = build_result(status: :failure, output: "RETRY: rate_limit exceeded")

      assert {:ok, :retry_stage} = TransitionEngine.next_stage(stage, result)
    end

    test "higher priority transitions are checked first" do
      stage =
        Stage.decision(:check, [
          %Transition{to_stage: :low_priority, condition: :always, priority: 1},
          %Transition{to_stage: :high_priority, condition: :always, priority: 10}
        ])

      result = build_result(status: :success)

      assert {:ok, :high_priority} = TransitionEngine.next_stage(stage, result)
    end

    test "returns error when no transition matches" do
      stage =
        Stage.decision(:check, [
          Transition.on_success(:success_stage)
        ])

      result = build_result(status: :failure)

      assert {:error, :no_transition_defined} = TransitionEngine.next_stage(stage, result)
    end
  end

  describe "has_explicit_transitions?/1" do
    test "returns false for stage with no transitions" do
      stage = Stage.agent(:impl, "prompt")
      refute TransitionEngine.has_explicit_transitions?(stage)
    end

    test "returns true for stage with transitions" do
      stage = Stage.decision(:check, [Transition.always(:next)])
      assert TransitionEngine.has_explicit_transitions?(stage)
    end
  end

  describe "has_shortcut_transitions?/1" do
    test "returns false for stage with no shortcuts" do
      stage = Stage.agent(:impl, "prompt")
      refute TransitionEngine.has_shortcut_transitions?(stage)
    end

    test "returns true for stage with on_success" do
      stage = Stage.agent(:impl, "prompt", on_success: :next)
      assert TransitionEngine.has_shortcut_transitions?(stage)
    end
  end

  describe "get_all_possible_transitions/1" do
    test "combines explicit and shortcut transitions" do
      stage =
        Stage.agent(:impl, "prompt",
          on_success: :review,
          on_failure: :retry,
          transitions: [Transition.on_timeout(:escalate)]
        )

      transitions = TransitionEngine.get_all_possible_transitions(stage)

      assert :review in transitions
      assert :retry in transitions
      assert :escalate in transitions
    end

    test "deduplicates transitions" do
      stage =
        Stage.agent(:impl, "prompt",
          on_success: :next,
          transitions: [Transition.on_success(:next)]
        )

      transitions = TransitionEngine.get_all_possible_transitions(stage)

      assert transitions == [:next]
    end
  end

  describe "build_transition_map/1" do
    test "builds map of stage transitions" do
      stages = [
        Stage.agent(:plan, "plan", on_success: :impl),
        Stage.agent(:impl, "impl", on_success: :review, on_failure: :retry),
        Stage.agent(:retry, "retry", on_success: :impl)
      ]

      map = TransitionEngine.build_transition_map(stages)

      assert map[:plan] == [:impl]
      assert MapSet.new(map[:impl]) == MapSet.new([:review, :retry])
      assert map[:retry] == [:impl]
    end
  end

  describe "validate_transitions/2" do
    test "returns :ok for valid transitions" do
      stage = Stage.agent(:impl, "prompt", on_success: :review)
      valid_ids = MapSet.new([:impl, :review])

      assert :ok = TransitionEngine.validate_transitions(stage, valid_ids)
    end

    test "returns error for invalid transitions" do
      stage = Stage.agent(:impl, "prompt", on_success: :nonexistent)
      valid_ids = MapSet.new([:impl, :review])

      assert {:error, [{:impl, :nonexistent}]} =
               TransitionEngine.validate_transitions(stage, valid_ids)
    end
  end

  defp build_result(opts) do
    %Result{
      stage_id: opts[:stage_id] || :test,
      session_id: opts[:session_id] || "test-session",
      started_at: DateTime.utc_now() |> DateTime.add(-60, :second),
      finished_at: DateTime.utc_now(),
      status: opts[:status] || :success,
      output: opts[:output] || "",
      exit_code: opts[:exit_code] || 0
    }
  end
end
