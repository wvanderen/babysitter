defmodule Babysitter.TD.HandoffTest do
  use ExUnit.Case, async: true

  alias Babysitter.TD.Handoff

  describe "parse_done/1" do
    test "parses JSON array of done items" do
      handoff = %Handoff{done: ~s(["Task 1", "Task 2"])}
      assert Handoff.parse_done(handoff) == ["Task 1", "Task 2"]
    end

    test "returns empty list for empty string" do
      handoff = %Handoff{done: ""}
      assert Handoff.parse_done(handoff) == []
    end

    test "returns empty list for nil" do
      handoff = %Handoff{done: nil}
      assert Handoff.parse_done(handoff) == []
    end

    test "returns empty list for invalid JSON" do
      handoff = %Handoff{done: "not valid json"}
      assert Handoff.parse_done(handoff) == []
    end
  end

  describe "parse_remaining/1" do
    test "parses JSON array of remaining items" do
      handoff = %Handoff{remaining: ~s(["Todo 1", "Todo 2"])}
      assert Handoff.parse_remaining(handoff) == ["Todo 1", "Todo 2"]
    end

    test "returns empty list for empty string" do
      handoff = %Handoff{remaining: ""}
      assert Handoff.parse_remaining(handoff) == []
    end
  end

  describe "parse_decisions/1" do
    test "parses JSON array of decisions" do
      handoff = %Handoff{decisions: ~s(["Use pattern X", "Avoid library Y"])}
      assert Handoff.parse_decisions(handoff) == ["Use pattern X", "Avoid library Y"]
    end

    test "returns empty list for empty string" do
      handoff = %Handoff{decisions: ""}
      assert Handoff.parse_decisions(handoff) == []
    end
  end

  describe "parse_uncertain/1" do
    test "parses JSON array of uncertain items" do
      handoff = %Handoff{uncertain: ~s(["Need clarification", "Unknown edge case"])}
      assert Handoff.parse_uncertain(handoff) == ["Need clarification", "Unknown edge case"]
    end

    test "returns empty list for empty string" do
      handoff = %Handoff{uncertain: ""}
      assert Handoff.parse_uncertain(handoff) == []
    end
  end
end
