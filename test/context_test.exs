defmodule Babysitter.ContextTest do
  use ExUnit.Case, async: true

  alias Babysitter.Context

  describe "empty_context/1" do
    test "creates empty context" do
      context = Context.empty_context("issue-1")

      assert context.issue_id == "issue-1"
      assert context.done == []
      assert context.remaining == []
      assert context.decisions == []
      assert context.uncertain == []
      assert context.handoff_count == 0
      assert context.last_handoff_at == nil
    end

    test "handles nil issue_id" do
      context = Context.empty_context(nil)
      assert context.issue_id == nil
    end
  end

  describe "has_context?/1" do
    test "returns false for empty context" do
      context = Context.empty_context("issue-1")
      refute Context.has_context?(context)
    end

    test "returns true when done has items" do
      context = %{Context.empty_context("issue-1") | done: ["item"]}
      assert Context.has_context?(context)
    end

    test "returns true when remaining has items" do
      context = %{Context.empty_context("issue-1") | remaining: ["item"]}
      assert Context.has_context?(context)
    end

    test "returns true when decisions has items" do
      context = %{Context.empty_context("issue-1") | decisions: ["item"]}
      assert Context.has_context?(context)
    end

    test "returns true when uncertain has items" do
      context = %{Context.empty_context("issue-1") | uncertain: ["item"]}
      assert Context.has_context?(context)
    end
  end

  describe "summary/1" do
    test "returns message for empty context" do
      context = Context.empty_context("issue-1")
      assert Context.summary(context) == "No previous context available."
    end

    test "formats done items" do
      context = %{Context.empty_context("issue-1") | done: ["Task 1", "Task 2"]}
      summary = Context.summary(context)

      assert summary =~ "## Completed"
      assert summary =~ "- Task 1"
      assert summary =~ "- Task 2"
    end

    test "formats remaining items" do
      context = %{Context.empty_context("issue-1") | remaining: ["Todo 1"]}
      summary = Context.summary(context)

      assert summary =~ "## Remaining"
      assert summary =~ "- Todo 1"
    end

    test "formats decisions" do
      context = %{Context.empty_context("issue-1") | decisions: ["Use PostgreSQL"]}
      summary = Context.summary(context)

      assert summary =~ "## Decisions Made"
      assert summary =~ "- Use PostgreSQL"
    end

    test "formats uncertain items" do
      context = %{Context.empty_context("issue-1") | uncertain: ["How to handle X"]}
      summary = Context.summary(context)

      assert summary =~ "## Needs Clarification"
      assert summary =~ "- How to handle X"
    end

    test "formats all sections" do
      context = %{
        Context.empty_context("issue-1")
        | done: ["Done"],
          remaining: ["Rem"],
          decisions: ["Dec"],
          uncertain: ["Unc"]
      }

      summary = Context.summary(context)

      assert summary =~ "## Completed"
      assert summary =~ "## Remaining"
      assert summary =~ "## Decisions Made"
      assert summary =~ "## Needs Clarification"
    end
  end

  describe "merge/1" do
    test "returns empty context for empty list" do
      context = Context.merge([])
      refute Context.has_context?(context)
    end

    test "merges done lists" do
      c1 = %{Context.empty_context("i1") | done: ["a", "b"]}
      c2 = %{Context.empty_context("i1") | done: ["b", "c"]}

      merged = Context.merge([c1, c2])

      assert "a" in merged.done
      assert "b" in merged.done
      assert "c" in merged.done
    end

    test "merges all fields" do
      c1 = %{Context.empty_context("i1") | done: ["a"], decisions: ["d1"]}
      c2 = %{Context.empty_context("i1") | remaining: ["r"], uncertain: ["u"]}

      merged = Context.merge([c1, c2])

      assert merged.done == ["a"]
      assert merged.remaining == ["r"]
      assert merged.decisions == ["d1"]
      assert merged.uncertain == ["u"]
    end

    test "latest context provides issue_id" do
      c1 = %{Context.empty_context("i1") | done: ["a"]}
      c2 = %{Context.empty_context("i2") | done: ["b"]}

      merged = Context.merge([c1, c2])

      assert merged.issue_id == "i1"
    end
  end
end
