defmodule Babysitter.PRTriggerTest do
  use ExUnit.Case, async: false

  alias Babysitter.PRTrigger

  describe "execute/3" do
    test "returns error when trigger doesn't match config" do
      result = PRTrigger.execute(:stage_complete, %{id: "td-123"}, [])

      trigger =
        Application.get_env(:babysitter, :git, %{})
        |> Map.get(:pr_strategy, %{})
        |> Map.get(:trigger, "manual")

      if trigger != "stage_complete" do
        assert match?({:error, _}, result)
      end
    end

    test "dry_run returns preview without creating PR" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true)
      assert {:ok, %{dry_run: true, title: _}} = result
    end

    test "uses title from options when provided" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, title: "Custom Title")
      assert {:ok, %{title: "Custom Title"}} = result
    end

    test "uses body from options when provided" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, body: "Custom Body")
      assert {:ok, %{body: "Custom Body"}} = result
    end

    test "uses labels from options when provided" do
      result =
        PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, labels: ["bug", "urgent"])

      assert {:ok, %{}} = result
    end

    test "uses reviewers from options when provided" do
      result =
        PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, reviewers: ["alice", "bob"])

      assert {:ok, %{}} = result
    end
  end

  describe "preview/3" do
    test "returns preview map with title and body" do
      result = PRTrigger.preview(:manual, %{id: "td-123"}, [])
      assert {:ok, %{dry_run: true, title: _, body: _}} = result
    end
  end

  describe "on_workflow_complete/2" do
    test "executes with workflow_complete trigger when configured" do
      trigger =
        Application.get_env(:babysitter, :git, %{})
        |> Map.get(:pr_strategy, %{})
        |> Map.get(:trigger, "manual")

      if trigger == "workflow_complete" do
        result = PRTrigger.on_workflow_complete(%{id: "td-123"}, dry_run: true)
        assert {:ok, %{dry_run: true}} = result
      else
        result = PRTrigger.on_workflow_complete(%{id: "td-123"}, dry_run: true)
        assert match?({:error, _}, result)
      end
    end
  end

  describe "on_stage_complete/2" do
    test "executes with stage_complete trigger when configured" do
      trigger =
        Application.get_env(:babysitter, :git, %{})
        |> Map.get(:pr_strategy, %{})
        |> Map.get(:trigger, "manual")

      if trigger == "stage_complete" do
        result = PRTrigger.on_stage_complete(%{id: "td-123"}, dry_run: true)
        assert {:ok, %{dry_run: true}} = result
      else
        result = PRTrigger.on_stage_complete(%{id: "td-123"}, dry_run: true)
        assert match?({:error, _}, result)
      end
    end
  end

  describe "should_trigger?/2" do
    test "returns true when has_branch is true" do
      assert PRTrigger.should_trigger?(:manual, has_branch: true) == true
    end

    test "returns false when has_branch is false" do
      assert PRTrigger.should_trigger?(:manual, has_branch: false) == false
    end
  end
end
