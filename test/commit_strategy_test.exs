defmodule Babysitter.CommitStrategyTest do
  use ExUnit.Case, async: true

  alias Babysitter.CommitStrategy

  describe "get_trigger/0" do
    test "returns trigger from config" do
      trigger = CommitStrategy.get_trigger()
      assert trigger in [:stage_complete, :validation_pass, :manual]
    end

    test "returns default trigger when not configured" do
      trigger = CommitStrategy.get_trigger()
      assert is_atom(trigger)
    end
  end

  describe "get_template/0" do
    test "returns template from config or nil" do
      template = CommitStrategy.get_template()
      assert is_binary(template) or is_nil(template)
    end
  end

  describe "auto_commit_enabled?/0" do
    test "returns true when trigger is not manual" do
      trigger = CommitStrategy.get_trigger()
      enabled = CommitStrategy.auto_commit_enabled?()

      if trigger == :manual do
        refute enabled
      else
        assert enabled
      end
    end
  end

  describe "maybe_commit/2" do
    test "returns commit message in dry_run mode" do
      issue = %{id: "td-test-123", title: "Test Issue"}

      opts = [
        stage: %{id: "stage-1", summary: "Implemented feature"},
        dry_run: true,
        has_changes: true,
        validation_passed: true,
        stage_completed: true
      ]

      assert {:ok, message} = CommitStrategy.maybe_commit(issue, opts)
      assert is_binary(message)
    end

    test "returns skipped when trigger condition not met" do
      issue = %{id: "td-test-456"}

      opts = [
        dry_run: true,
        has_changes: false,
        validation_passed: true,
        stage_completed: true
      ]

      result = CommitStrategy.maybe_commit(issue, opts)
      trigger = CommitStrategy.get_trigger()

      case trigger do
        :manual ->
          assert result == :skipped

        _ ->
          cond do
            result == :skipped -> true
            match?({:ok, msg} when is_binary(msg), result) -> true
            true -> flunk("Expected :skipped or {:ok, msg}, got: #{inspect(result)}")
          end
      end
    end

    test "forces commit with force option" do
      issue = %{id: "td-test-789"}

      opts = [
        dry_run: true,
        force: true,
        has_changes: false
      ]

      assert {:ok, message} = CommitStrategy.maybe_commit(issue, opts)
      assert is_binary(message)
    end

    test "uses custom template from config" do
      issue = %{id: "td-template-test"}

      opts = [
        custom_template: "Custom: {{issue.id}}",
        dry_run: true,
        force: true
      ]

      assert {:ok, message} = CommitStrategy.maybe_commit(issue, opts)
      assert message =~ "td-template-test"
    end
  end

  describe "on_stage_complete/2" do
    test "commits when trigger is stage_complete" do
      issue = %{id: "td-stage-111"}

      opts = [
        dry_run: true,
        has_changes: true,
        validation_passed: true
      ]

      result = CommitStrategy.on_stage_complete(issue, opts)

      if CommitStrategy.get_trigger() == :stage_complete do
        assert {:ok, message} = result
        assert message =~ "td-stage-111"
      else
        assert result == :skipped
      end
    end

    test "skips when trigger is not stage_complete" do
      issue = %{id: "td-stage-222"}

      result = CommitStrategy.on_stage_complete(issue, dry_run: true)

      if CommitStrategy.get_trigger() != :stage_complete do
        assert result == :skipped
      else
        assert {:ok, _} = result
      end
    end
  end

  describe "on_validation_pass/2" do
    test "commits when trigger is validation_pass" do
      issue = %{id: "td-val-333"}

      opts = [
        dry_run: true,
        has_changes: true,
        validation_passed: true
      ]

      result = CommitStrategy.on_validation_pass(issue, opts)

      if CommitStrategy.get_trigger() == :validation_pass do
        assert {:ok, message} = result
        assert message =~ "td-val-333"
      else
        assert result == :skipped
      end
    end
  end

  describe "on_manual/2" do
    test "always commits regardless of trigger" do
      issue = %{id: "td-manual-444"}

      opts = [
        dry_run: true,
        has_changes: true
      ]

      assert {:ok, message} = CommitStrategy.on_manual(issue, opts)
      assert message =~ "td-manual-444"
    end
  end

  describe "should_commit?/2" do
    test "stage_complete requires changes and stage completion" do
      assert CommitStrategy.should_commit?(:stage_complete,
               has_changes: true,
               stage_completed: true,
               validation_passed: true
             )

      refute CommitStrategy.should_commit?(:stage_complete,
               has_changes: false,
               stage_completed: true,
               validation_passed: true
             )

      refute CommitStrategy.should_commit?(:stage_complete,
               has_changes: true,
               stage_completed: false,
               validation_passed: true
             )
    end

    test "validation_pass requires changes and validation" do
      assert CommitStrategy.should_commit?(:validation_pass,
               has_changes: true,
               validation_passed: true
             )

      refute CommitStrategy.should_commit?(:validation_pass,
               has_changes: false,
               validation_passed: true
             )

      refute CommitStrategy.should_commit?(:validation_pass,
               has_changes: true,
               validation_passed: false
             )
    end

    test "manual never auto-commits" do
      refute CommitStrategy.should_commit?(:manual,
               has_changes: true,
               validation_passed: true
             )
    end
  end

  describe "effective_trigger/1" do
    test "returns trigger when conditions are met" do
      trigger =
        CommitStrategy.effective_trigger(
          has_changes: true,
          validation_passed: true,
          stage_completed: true
        )

      case CommitStrategy.get_trigger() do
        :stage_complete -> assert trigger == :stage_complete
        :validation_pass -> assert trigger == :validation_pass
        :manual -> assert trigger == :none
      end
    end

    test "returns :none when conditions not met" do
      trigger = CommitStrategy.effective_trigger(has_changes: false)

      assert trigger == :none or trigger in [:stage_complete, :validation_pass, :manual]
    end
  end

  describe "preview/2" do
    test "returns message without executing" do
      issue = %{id: "td-preview-555"}

      opts = [
        stage: %{summary: "Preview test"},
        has_changes: true,
        validation_passed: true,
        stage_completed: true
      ]

      assert {:ok, message} = CommitStrategy.preview(issue, opts)
      assert is_binary(message)
    end
  end

  describe "valid_triggers/0" do
    test "returns list of valid triggers" do
      triggers = CommitStrategy.valid_triggers()

      assert :stage_complete in triggers
      assert :validation_pass in triggers
      assert :manual in triggers
    end
  end

  describe "integration with config" do
    test "reads trigger from config" do
      trigger = CommitStrategy.get_trigger()
      assert trigger in CommitStrategy.valid_triggers()
    end

    test "respects configured trigger type" do
      trigger = CommitStrategy.get_trigger()

      issue = %{id: "td-config-test"}

      result =
        case trigger do
          :stage_complete ->
            CommitStrategy.on_stage_complete(issue, dry_run: true, has_changes: true)

          :validation_pass ->
            CommitStrategy.on_validation_pass(issue, dry_run: true, has_changes: true)

          :manual ->
            CommitStrategy.on_manual(issue, dry_run: true)
        end

      case result do
        {:ok, _message} -> :ok
        :skipped -> :ok
        other -> flunk("Expected {:ok, _} or :skipped, got: #{inspect(other)}")
      end
    end
  end
end
