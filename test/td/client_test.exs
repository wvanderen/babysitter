defmodule Babysitter.TD.ClientTest do
  use ExUnit.Case, async: false

  alias Babysitter.TD.{Client, Issue, Repo}

  setup do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert!(%Issue{
      id: "td-test-1",
      title: "Test Issue Alpha",
      description: "Alpha test description",
      status: "open",
      type: "task",
      priority: "P0",
      created_at: now,
      updated_at: now
    })

    Repo.insert!(%Issue{
      id: "td-test-2",
      title: "Test Issue Beta",
      description: "Beta test description",
      status: "in_review",
      type: "epic",
      priority: "P1",
      parent_id: "td-parent-1",
      created_at: now,
      updated_at: now
    })

    on_exit(fn ->
      Repo.delete_all(Issue)
    end)

    :ok
  end

  describe "get_issue/1" do
    test "returns issue by id" do
      issue = Client.get_issue("td-test-1")
      assert issue != nil
      assert issue.id == "td-test-1"
      assert issue.title == "Test Issue Alpha"
    end

    test "returns nil for non-existent id" do
      assert Client.get_issue("nonexistent-xyz-123") == nil
    end
  end

  describe "list_issues/1" do
    test "lists all issues" do
      issues = Client.list_issues()
      assert length(issues) == 2
    end

    test "filters by status" do
      issues = Client.list_issues(status: "open")
      assert length(issues) == 1
      assert hd(issues).status == "open"
    end

    test "filters by type" do
      issues = Client.list_issues(type: "epic")
      assert length(issues) == 1
      assert hd(issues).type == "epic"
    end

    test "filters by priority" do
      issues = Client.list_issues(priority: "P0")
      assert length(issues) == 1
      assert hd(issues).priority == "P0"
    end

    test "filters by parent_id" do
      issues = Client.list_issues(parent_id: "td-parent-1")
      assert length(issues) == 1
      assert hd(issues).parent_id == "td-parent-1"
    end
  end

  describe "open_issues/0" do
    test "returns only open issues" do
      issues = Client.open_issues()
      assert length(issues) == 1
      assert Enum.all?(issues, &(&1.status == "open"))
    end
  end

  describe "by_priority/1" do
    test "returns issues by priority" do
      issues = Client.by_priority("P1")
      assert length(issues) == 1
      assert hd(issues).priority == "P1"
    end
  end

  describe "search/1" do
    test "searches by title" do
      issues = Client.search("Alpha")
      assert length(issues) == 1
    end

    test "searches by description" do
      issues = Client.search("Beta")
      assert length(issues) == 1
    end

    test "returns empty for no matches" do
      issues = Client.search("xyznonexistent123456")
      assert issues == []
    end
  end

  describe "count_by_status/1" do
    test "counts open issues" do
      count = Client.count_by_status("open")
      assert count == 1
    end

    test "counts in_review issues" do
      count = Client.count_by_status("in_review")
      assert count == 1
    end

    test "returns 0 for non-existent status" do
      count = Client.count_by_status("nonexistent")
      assert count == 0
    end
  end
end
