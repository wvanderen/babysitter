defmodule Babysitter.EscalationHandlerTest do
  use ExUnit.Case, async: false

  alias Babysitter.EscalationHandler

  @moduletag :escalation

  describe "should_escalate?/1" do
    test "returns true for escalate action" do
      assert EscalationHandler.should_escalate?(%{action: :escalate}) == true
    end

    test "returns false for ok action" do
      refute EscalationHandler.should_escalate?(%{action: :ok})
    end

    test "returns false for retry action" do
      refute EscalationHandler.should_escalate?(%{action: :retry})
    end

    test "returns false for restart action" do
      refute EscalationHandler.should_escalate?(%{action: :restart})
    end

    test "returns false for skip action" do
      refute EscalationHandler.should_escalate?(%{action: :skip})
    end

    test "returns false for nil" do
      refute EscalationHandler.should_escalate?(nil)
    end

    test "returns false for empty map" do
      refute EscalationHandler.should_escalate?(%{})
    end
  end

  describe "escalate/2" do
    @tag :td_cli
    test "succeeds without issue_id (only broadcasts)" do
      result =
        EscalationHandler.escalate("session-123",
          issue_id: nil,
          reason: "Test escalation"
        )

      assert {:ok, :escalated} = result
    end

    @tag :td_cli
    @tag :skip
    test "escalates with issue_id and handoff" do
      result =
        EscalationHandler.escalate("session-456",
          issue_id: "td-test-escalation",
          reason: "Test escalation from unit test",
          handoff_note: "Automated test handoff",
          done: ["Verified escalation works"],
          remaining: ["Integration testing"]
        )

      assert {:ok, :escalated} = result
    end
  end
end
