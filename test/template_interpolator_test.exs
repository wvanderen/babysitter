defmodule Babysitter.TemplateInterpolatorTest do
  use ExUnit.Case, async: true

  alias Babysitter.TemplateInterpolator

  describe "interpolate/3 with basic placeholders" do
    test "interpolates simple string values" do
      template = "Issue: {{issue.id}} - {{issue.title}}"
      context = %{issue: %{id: "td-123", title: "Fix the bug"}}

      assert TemplateInterpolator.interpolate(template, context) ==
               "Issue: td-123 - Fix the bug"
    end

    test "handles nested paths" do
      template = "Done: {{issue.last_handoff.done}}"
      context = %{issue: %{last_handoff: %{done: ["Task 1", "Task 2"]}}}

      result = TemplateInterpolator.interpolate(template, context)
      assert result =~ "- Task 1"
      assert result =~ "- Task 2"
    end

    test "formats lists with bullet points by default" do
      template = "{{issue.last_handoff.remaining}}"
      context = %{issue: %{last_handoff: %{remaining: ["A", "B", "C"]}}}

      assert TemplateInterpolator.interpolate(template, context) == "- A\n- B\n- C"
    end

    test "returns empty string for empty lists" do
      template = "Done: {{issue.last_handoff.done}}"
      context = %{issue: %{last_handoff: %{done: []}}}

      assert TemplateInterpolator.interpolate(template, context) == "Done: "
    end

    test "handles missing values with :empty option" do
      template = "Branch: {{git.branch}}"
      context = %{}

      assert TemplateInterpolator.interpolate(template, context) == "Branch: "
    end

    test "handles missing values with :keep option" do
      template = "Branch: {{git.branch}}"
      context = %{}

      assert TemplateInterpolator.interpolate(template, context, missing: :keep) ==
               "Branch: {{git.branch}}"
    end

    test "raises on missing values with :raise option" do
      template = "Branch: {{git.branch}}"
      context = %{}

      assert_raise ArgumentError, ~r/Missing value for placeholder/, fn ->
        TemplateInterpolator.interpolate(template, context, missing: :raise)
      end
    end
  end

  describe "interpolate/3 with filters" do
    test "join filter with custom separator" do
      template = "Labels: {{issue.labels | join: \", \"}}"
      context = %{issue: %{labels: ["bug", "urgent", "backend"]}}

      assert TemplateInterpolator.interpolate(template, context) ==
               "Labels: bug, urgent, backend"
    end

    test "first filter returns first list item" do
      template = "First: {{issue.labels | first}}"
      context = %{issue: %{labels: ["a", "b", "c"]}}

      assert TemplateInterpolator.interpolate(template, context) == "First: a"
    end

    test "first filter returns empty for empty list" do
      template = "First: {{issue.labels | first}}"
      context = %{issue: %{labels: []}}

      assert TemplateInterpolator.interpolate(template, context) == "First: "
    end

    test "last filter returns last list item" do
      template = "Last: {{issue.labels | last}}"
      context = %{issue: %{labels: ["a", "b", "c"]}}

      assert TemplateInterpolator.interpolate(template, context) == "Last: c"
    end

    test "count filter returns list length" do
      template = "Total: {{issue.labels | count}}"
      context = %{issue: %{labels: ["a", "b", "c"]}}

      assert TemplateInterpolator.interpolate(template, context) == "Total: 3"
    end

    test "count filter works on empty list" do
      template = "Total: {{issue.labels | count}}"
      context = %{issue: %{labels: []}}

      assert TemplateInterpolator.interpolate(template, context) == "Total: 0"
    end
  end

  describe "interpolate/3 with different value types" do
    test "converts atoms to strings" do
      template = "Status: {{issue.status}}"
      context = %{issue: %{status: :in_progress}}

      assert TemplateInterpolator.interpolate(template, context) == "Status: in_progress"
    end

    test "converts integers to strings" do
      template = "Count: {{issue.count}}"
      context = %{issue: %{count: 42}}

      assert TemplateInterpolator.interpolate(template, context) == "Count: 42"
    end

    test "handles nil values" do
      template = "Value: {{issue.empty}}"
      context = %{issue: %{empty: nil}}

      assert TemplateInterpolator.interpolate(template, context) == "Value: "
    end
  end

  describe "build_context/2" do
    test "builds context from issue struct" do
      issue = %{id: "td-123", title: "Fix bug", status: "open", priority: "P0"}

      context = TemplateInterpolator.build_context(issue)

      assert context.issue.id == "td-123"
      assert context.issue.title == "Fix bug"
      assert context.issue.status == "open"
      assert context.issue.priority == "P0"
    end

    test "includes last_handoff context" do
      issue = %{id: "td-123", title: "Fix bug"}
      handoff = %{done: ["A", "B"], remaining: ["C"]}

      context = TemplateInterpolator.build_context(issue, last_handoff: handoff)

      assert context.issue.last_handoff.done == ["A", "B"]
      assert context.issue.last_handoff.remaining == ["C"]
    end

    test "includes stage context" do
      issue = %{id: "td-123"}
      stage = %{id: "build", name: "Build Stage", summary: "All tests pass"}

      context = TemplateInterpolator.build_context(issue, stage: stage)

      assert context.stage.id == "build"
      assert context.stage.name == "Build Stage"
      assert context.stage.summary == "All tests pass"
    end

    test "includes session context" do
      issue = %{id: "td-123"}
      session = %{id: "ses-abc", branch: "feature/test"}

      context = TemplateInterpolator.build_context(issue, session: session)

      assert context.session.id == "ses-abc"
      assert context.session.branch == "feature/test"
    end

    test "includes git context with short commit" do
      issue = %{id: "td-123"}
      git = %{branch: "main", commit: "abcd1234567890", message: "Initial commit"}

      context = TemplateInterpolator.build_context(issue, git: git)

      assert context.git.branch == "main"
      assert context.git.commit == "abcd1234567890"
      assert context.git.short_commit == "abcd123"
      assert context.git.message == "Initial commit"
    end

    test "handles nil issue" do
      context = TemplateInterpolator.build_context(nil)

      assert context.issue.id == ""
      assert context.issue.title == ""
    end

    test "parses comma-separated labels" do
      issue = %{id: "td-123", labels: "bug, urgent, backend"}

      context = TemplateInterpolator.build_context(issue)

      assert context.issue.labels == ["bug", "urgent", "backend"]
    end

    test "handles empty labels" do
      issue = %{id: "td-123", labels: ""}

      context = TemplateInterpolator.build_context(issue)

      assert context.issue.labels == []
    end
  end

  describe "integration with commit message template" do
    test "generates commit message from config template" do
      template = "{{issue.id}}: {{issue.title}}\n\n{{stage.summary}}"

      context =
        TemplateInterpolator.build_context(
          %{id: "td-123", title: "Fix login bug"},
          stage: %{summary: "Fixed authentication flow"}
        )

      result = TemplateInterpolator.interpolate(template, context)

      assert result == "td-123: Fix login bug\n\nFixed authentication flow"
    end

    test "includes handoff context in template" do
      template = """
      {{issue.id}}: {{issue.title}}

      Completed:
      {{issue.last_handoff.done}}
      """

      issue = %{id: "td-456", title: "Add feature"}
      handoff = %{done: ["Wrote tests", "Implemented logic"], remaining: []}

      context = TemplateInterpolator.build_context(issue, last_handoff: handoff)
      result = TemplateInterpolator.interpolate(template, context)

      assert result =~ "td-456: Add feature"
      assert result =~ "- Wrote tests"
      assert result =~ "- Implemented logic"
    end
  end
end
