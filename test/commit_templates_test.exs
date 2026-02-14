defmodule Babysitter.CommitTemplatesTest do
  use ExUnit.Case, async: true

  alias Babysitter.CommitTemplates

  describe "get_template/1" do
    test "returns stage_complete template" do
      template = CommitTemplates.get_template(:stage_complete)
      assert String.contains?(template, "{{issue.id}}")
      assert String.contains?(template, "{{stage.summary}}")
    end

    test "returns validation_pass template" do
      template = CommitTemplates.get_template(:validation_pass)
      assert String.contains?(template, "Validated")
      assert String.contains?(template, "{{issue.id}}")
    end

    test "returns manual template" do
      template = CommitTemplates.get_template(:manual)
      assert String.contains?(template, "{{issue.id}}")
      assert String.contains?(template, "{{stage.summary}}")
    end

    test "returns nil for unknown trigger" do
      assert CommitTemplates.get_template(:unknown) == nil
    end
  end

  describe "build_message/3" do
    test "builds stage_complete message with issue context" do
      issue = %{id: "td-123", title: "Fix bug"}
      opts = [stage: %{summary: "Completed the fix"}]

      message = CommitTemplates.build_message(:stage_complete, issue, opts)

      assert String.contains?(message, "td-123")
      assert String.contains?(message, "Completed the fix")
    end

    test "builds validation_pass message" do
      issue = %{id: "td-456", title: "Add feature"}
      opts = [stage: %{summary: "All tests pass"}]

      message = CommitTemplates.build_message(:validation_pass, issue, opts)

      assert String.contains?(message, "td-456")
      assert String.contains?(message, "All tests pass")
    end

    test "builds manual message with handoff context" do
      issue = %{id: "td-789", title: "Refactor"}

      opts = [
        stage: %{summary: "Manual commit"},
        last_handoff: %{done: ["Item 1", "Item 2"]}
      ]

      message = CommitTemplates.build_message(:manual, issue, opts)

      assert String.contains?(message, "td-789")
      assert String.contains?(message, "Item 1")
    end

    test "raises for unknown trigger" do
      issue = %{id: "td-123"}

      assert_raise ArgumentError, ~r/Unknown template trigger/, fn ->
        CommitTemplates.build_message(:unknown, issue, [])
      end
    end
  end

  describe "build_with_template/3" do
    test "interpolates custom template" do
      template = "Issue {{issue.id}}: {{issue.title}}"
      issue = %{id: "td-abc", title: "Test Issue"}

      message = CommitTemplates.build_with_template(template, issue, [])

      assert message == "Issue td-abc: Test Issue"
    end

    test "interpolates stage context" do
      template = "Stage: {{stage.name}} - {{stage.summary}}"
      issue = %{}
      opts = [stage: %{name: "build", summary: "Built successfully"}]

      message = CommitTemplates.build_with_template(template, issue, opts)

      assert message == "Stage: build - Built successfully"
    end

    test "handles empty context gracefully" do
      template = "Issue: {{issue.id}}"
      issue = %{}

      message = CommitTemplates.build_with_template(template, issue, [])

      assert message == "Issue: "
    end
  end

  describe "triggers/0" do
    test "returns list of trigger atoms" do
      triggers = CommitTemplates.triggers()

      assert :stage_complete in triggers
      assert :validation_pass in triggers
      assert :manual in triggers
    end
  end

  describe "all_templates/0" do
    test "returns map of all templates" do
      templates = CommitTemplates.all_templates()

      assert is_map(templates)
      assert Map.has_key?(templates, :stage_complete)
      assert Map.has_key?(templates, :validation_pass)
      assert Map.has_key?(templates, :manual)
    end
  end
end
