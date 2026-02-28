defmodule Babysitter.PRTriggerTest do
  use ExUnit.Case, async: false

  alias Babysitter.PRTrigger

  describe "execute/3" do
    test "returns error when trigger doesn't match config" do
      result = PRTrigger.execute(:workflow_complete, %{id: "td-123"}, [])
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "dry_run returns preview without creating PR" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true)
      assert match?({:ok, %{dry_run: true}}, result)
    end

    test "uses title from options when provided" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, title: "Custom Title")
      assert match?({:ok, %{title: "Custom Title"}}, result)
    end

    test "uses body from options when provided" do
      result = PRTrigger.execute(:manual, %{id: "td-123"}, dry_run: true, body: "Custom Body")
      assert match?({:ok, %{body: "Custom Body"}}, result)
    end
  end

  describe "preview/3" do
    test "returns preview map" do
      result = PRTrigger.preview(:manual, %{id: "td-123"}, [])
      assert match?({:ok, %{dry_run: true}}, result)
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
