defmodule Babysitter.CommitTriggerTest do
  use ExUnit.Case, async: true

  alias Babysitter.CommitTrigger

  describe "execute/3" do
    test "returns commit message in dry_run mode" do
      issue = %{id: "td-test-123", title: "Test Issue"}

      opts = [
        stage: %{id: "stage-1", summary: "Implemented feature"},
        dry_run: true
      ]

      assert {:ok, message} = CommitTrigger.execute(:stage_complete, issue, opts)
      assert message =~ "td-test-123"
      assert message =~ "Implemented feature"
    end

    test "uses custom template when provided" do
      issue = %{id: "td-custom-456"}

      opts = [
        custom_template: "Custom: {{issue.id}}",
        dry_run: true
      ]

      assert {:ok, "Custom: td-custom-456"} = CommitTrigger.execute(:manual, issue, opts)
    end

    test "builds validation_pass message" do
      issue = %{id: "td-val-789"}

      opts = [
        stage: %{summary: "All tests pass"},
        dry_run: true
      ]

      assert {:ok, message} = CommitTrigger.execute(:validation_pass, issue, opts)
      assert message =~ "Validated"
      assert message =~ "td-val-789"
    end

    test "builds manual message" do
      issue = %{id: "td-manual-111"}

      opts = [
        stage: %{summary: "Manual commit"},
        dry_run: true
      ]

      assert {:ok, message} = CommitTrigger.execute(:manual, issue, opts)
      assert message =~ "td-manual-111"
    end
  end

  describe "execute_with_template/3" do
    test "executes with custom template" do
      issue = %{id: "td-template-222"}

      opts = [dry_run: true]

      assert {:ok, message} =
               CommitTrigger.execute_with_template(
                 "Issue: {{issue.id}} done",
                 issue,
                 opts
               )

      assert message == "Issue: td-template-222 done"
    end
  end

  describe "preview/3" do
    test "returns message without executing commit" do
      issue = %{id: "td-preview-333"}

      opts = [stage: %{summary: "Preview test"}]

      assert {:ok, message} = CommitTrigger.preview(:stage_complete, issue, opts)
      assert message =~ "td-preview-333"
    end
  end

  describe "on_stage_complete/2" do
    test "triggers stage_complete commit" do
      issue = %{id: "td-stage-444"}

      opts = [dry_run: true, stage: %{summary: "Done"}]

      assert {:ok, message} = CommitTrigger.on_stage_complete(issue, opts)
      assert message =~ "Completed"
      assert message =~ "td-stage-444"
    end
  end

  describe "on_validation_pass/2" do
    test "triggers validation_pass commit" do
      issue = %{id: "td-val-555"}

      opts = [dry_run: true, stage: %{summary: "Validated"}]

      assert {:ok, message} = CommitTrigger.on_validation_pass(issue, opts)
      assert message =~ "Validated"
      assert message =~ "td-val-555"
    end
  end

  describe "on_manual/2" do
    test "triggers manual commit" do
      issue = %{id: "td-manual-666"}

      opts = [dry_run: true, stage: %{summary: "Manual"}]

      assert {:ok, message} = CommitTrigger.on_manual(issue, opts)
      assert message =~ "td-manual-666"
    end
  end

  describe "should_trigger?/2" do
    test "returns true for stage_complete with changes and validation" do
      opts = [has_changes: true, validation_passed: true]

      assert CommitTrigger.should_trigger?(:stage_complete, opts)
    end

    test "returns false for stage_complete without changes" do
      opts = [has_changes: false, validation_passed: true]

      refute CommitTrigger.should_trigger?(:stage_complete, opts)
    end

    test "returns false for stage_complete with failed validation" do
      opts = [has_changes: true, validation_passed: false]

      refute CommitTrigger.should_trigger?(:stage_complete, opts)
    end

    test "returns true for manual with changes" do
      opts = [has_changes: true]

      assert CommitTrigger.should_trigger?(:manual, opts)
    end

    test "returns false for manual without changes" do
      opts = [has_changes: false]

      refute CommitTrigger.should_trigger?(:manual, opts)
    end

    test "returns true for validation_pass with changes and validation" do
      opts = [has_changes: true, validation_passed: true]

      assert CommitTrigger.should_trigger?(:validation_pass, opts)
    end
  end

  describe "integration with templates" do
    test "interpolates issue context" do
      issue = %{
        id: "td-int-777",
        title: "Integration Test"
      }

      opts = [
        stage: %{summary: "Stage output"},
        last_handoff: %{done: ["Completed items"]},
        dry_run: true
      ]

      assert {:ok, message} = CommitTrigger.execute(:stage_complete, issue, opts)
      assert message =~ "td-int-777"
      assert message =~ "Stage output"
      assert message =~ "Completed items"
    end
  end
end
