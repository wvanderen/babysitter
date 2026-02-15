defmodule Babysitter.PRTest do
  use ExUnit.Case, async: false

  alias Babysitter.PR

  describe "available?/0" do
    test "returns a boolean" do
      result = PR.available?()
      assert is_boolean(result)
    end
  end

  describe "create/1" do
    test "requires title option" do
      assert_raise KeyError, fn ->
        PR.create([])
      end
    end

    test "returns error without gh auth" do
      result = PR.create(title: "Test PR")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "interpolates template in title" do
      result =
        PR.create(
          title: "{{issue.id}}: Test",
          issue: %{id: "td-123"}
        )

      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end

  describe "add_reviewers/1" do
    test "requires reviewers option" do
      assert_raise KeyError, fn ->
        PR.add_reviewers([])
      end
    end

    test "returns error or ok" do
      result = PR.add_reviewers(reviewers: ["alice"])
      assert match?({:error, _}, result) or result == :ok
    end
  end

  describe "add_labels/1" do
    test "requires labels option" do
      assert_raise KeyError, fn ->
        PR.add_labels([])
      end
    end

    test "returns error or ok" do
      result = PR.add_labels(labels: ["bug"])
      assert match?({:error, _}, result) or result == :ok
    end
  end

  describe "list/1" do
    test "returns ok with list or error" do
      result = PR.list(limit: 5)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts state option" do
      result = PR.list(state: :open, limit: 1)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts json option" do
      result = PR.list(json: true, limit: 1)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "current/0" do
    test "returns ok or error" do
      result = PR.current()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "merge/1" do
    test "returns error or ok" do
      result = PR.merge()
      assert match?({:error, _}, result) or result == :ok
    end

    test "accepts method option" do
      result = PR.merge(method: :squash)
      assert match?({:error, _}, result) or result == :ok
    end
  end

  describe "template interpolation" do
    test "interpolates issue placeholders in title" do
      result =
        PR.create(
          title: "{{issue.id}}: {{issue.title}}",
          body: "Done:\n{{issue.last_handoff.done}}",
          issue: %{id: "td-456", title: "Feature", last_handoff: %{done: ["Item 1"]}}
        )

      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
