defmodule Babysitter.TD.ClientTest do
  use ExUnit.Case, async: false

  alias Babysitter.TD.{Client, Handoff, Issue, Repo}

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
      Repo.delete_all(Handoff)
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

  describe "get_latest_handoff/1" do
    test "returns nil when no handoffs exist" do
      assert Client.get_latest_handoff("td-test-1") == nil
    end

    test "returns latest handoff for issue" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      earlier = NaiveDateTime.add(now, -3600, :second)

      Repo.insert!(%Handoff{
        id: "handoff-1",
        issue_id: "td-test-1",
        session_id: "session-1",
        done: ~s(["Task completed"]),
        remaining: ~s(["Task remaining"]),
        decisions: ~s(["Decision made"]),
        uncertain: ~s(["Uncertain item"]),
        timestamp: earlier
      })

      Repo.insert!(%Handoff{
        id: "handoff-2",
        issue_id: "td-test-1",
        session_id: "session-2",
        done: ~s(["Later task"]),
        remaining: ~s([]),
        decisions: ~s([]),
        uncertain: ~s([]),
        timestamp: now
      })

      handoff = Client.get_latest_handoff("td-test-1")
      assert handoff != nil
      assert handoff.id == "handoff-2"
      assert handoff.done == ~s(["Later task"])
    end
  end

  describe "get_handoffs/1" do
    test "returns empty list when no handoffs exist" do
      assert Client.get_handoffs("td-test-1") == []
    end

    test "returns all handoffs for issue ordered by timestamp desc" do
      now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      earlier = NaiveDateTime.add(now, -3600, :second)

      Repo.insert!(%Handoff{
        id: "handoff-old",
        issue_id: "td-test-1",
        session_id: "session-1",
        done: ~s(["Old"]),
        remaining: ~s([]),
        decisions: ~s([]),
        uncertain: ~s([]),
        timestamp: earlier
      })

      Repo.insert!(%Handoff{
        id: "handoff-new",
        issue_id: "td-test-1",
        session_id: "session-2",
        done: ~s(["New"]),
        remaining: ~s([]),
        decisions: ~s([]),
        uncertain: ~s([]),
        timestamp: now
      })

      handoffs = Client.get_handoffs("td-test-1")
      assert length(handoffs) == 2
      assert hd(handoffs).id == "handoff-new"
      assert List.last(handoffs).id == "handoff-old"
    end
  end
end
