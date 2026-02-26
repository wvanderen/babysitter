defmodule Babysitter.TD.WriterTest do
  use ExUnit.Case, async: false

  alias Babysitter.TD.{CLI, Handoff, Writer}

  @moduletag :td_cli

  setup do
    unique_suffix = :rand.uniform(1_000_000)
    {:ok, output} = CLI.execute_td(["add", "Writer Test #{unique_suffix}", "--minor"])

    issue_id =
      case Regex.run(~r/CREATED (td-[a-f0-9]+)/, output) do
        [_, id] -> id
        _ -> nil
      end

    on_exit(fn ->
      if issue_id, do: CLI.execute_td(["close", issue_id])
    end)

    {:ok, issue_id: issue_id}
  end

  describe "create_handoff/2" do
    test "creates handoff with done/remaining/uncertain fields via CLI", %{issue_id: issue_id} do
      opts = [
        done: ["Completed task 1", "Completed task 2"],
        remaining: ["Remaining task"],
        uncertain: ["Need clarification on X"],
        decisions: ["Use PostgreSQL for DB"]
      ]

      result = Writer.create_handoff(issue_id, opts)

      assert {:ok, output} = result
      assert output =~ "HANDOFF RECORDED"

      {:ok, show_output} = CLI.execute_td(["show", issue_id])
      assert show_output =~ "Completed task 1"
      assert show_output =~ "Completed task 2"
      assert show_output =~ "Remaining task"
    end

    test "creates handoff with note only", %{issue_id: issue_id} do
      result = Writer.create_handoff(issue_id, note: "Simple handoff note")
      assert {:ok, _} = result
    end

    test "creates handoff for any issue id (td allows new ids)" do
      unique = :rand.uniform(1_000_000)
      {:ok, _} = CLI.execute_td(["add", "Temp Issue #{unique}", "--minor"])

      {:ok, show_output} = CLI.execute_td(["list", "--json"])
      issues = Jason.decode!(show_output)

      temp_issue =
        Enum.find(issues, fn i -> String.contains?(i["title"], "Temp Issue #{unique}") end)

      result = Writer.create_handoff(temp_issue["id"], done: ["Task"])
      assert {:ok, _} = result

      CLI.execute_td(["close", temp_issue["id"]])
    end

    test "creates handoff from map context", %{issue_id: issue_id} do
      context = %{
        done: ["Done 1"],
        remaining: ["Rem 1"],
        uncertain: ["Unc 1"],
        decisions: ["Dec 1"]
      }

      result = Writer.create_handoff(issue_id, context)
      assert {:ok, _} = result
    end
  end

  describe "add_log/2" do
    test "adds progress log to issue via CLI", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, "Progress update: halfway done", type: "progress")
      assert {:ok, _} = result
    end

    test "adds blocker log to issue via CLI", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, "Blocked on external API", type: "blocker")
      assert {:ok, _} = result
    end

    test "adds decision log to issue via CLI", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, "Decided to use Redis for caching", type: "decision")
      assert {:ok, _} = result
    end

    test "adds log without type via CLI", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, "Generic update")
      assert {:ok, _} = result
    end

    test "returns error for empty message", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, "")
      assert {:error, "Message cannot be empty", 1} = result
    end

    test "returns error for nil message", %{issue_id: issue_id} do
      result = Writer.add_log(issue_id, nil)
      assert {:error, "Message cannot be empty", 1} = result
    end
  end

  describe "submit_for_review/2" do
    test "submits issue for review via CLI", %{issue_id: issue_id} do
      CLI.start_issue(issue_id)

      Writer.create_handoff(issue_id, done: ["Task complete"])

      result = Writer.submit_for_review(issue_id, reason: "Implementation complete")
      assert {:ok, _} = result

      {:ok, show_output} = CLI.execute_td(["show", issue_id, "--short"])
      assert show_output =~ "in_review"
    end

    test "returns warning and auto-creates handoff when submitting for review without handoff", %{
      issue_id: issue_id
    } do
      CLI.start_issue(issue_id)

      result = Writer.submit_for_review(issue_id, reason: "Implementation complete")
      assert {:ok, output} = result
      assert output =~ "auto-created minimal handoff"

      {:ok, show_output} = CLI.execute_td(["show", issue_id, "--short"])
      assert show_output =~ "in_review"
    end
  end

  describe "write_context/3" do
    test "writes full context with handoff and log", %{issue_id: issue_id} do
      CLI.start_issue(issue_id)

      context = %{
        done: ["Task 1", "Task 2"],
        remaining: ["Task 3"],
        uncertain: ["Question about Y"],
        decisions: ["Use API v2"]
      }

      result = Writer.write_context(issue_id, context, message: "Session complete")

      assert {:ok, _} = result

      {:ok, show_output} = CLI.execute_td(["show", issue_id])
      assert show_output =~ "Task 1"
      assert show_output =~ "Task 2"
    end

    test "writes context without log message", %{issue_id: issue_id} do
      context = %{done: ["Only done items"]}

      result = Writer.write_context(issue_id, context)
      assert {:ok, _} = result
    end
  end

  describe "update_status/2" do
    test "blocks issue with reason", %{issue_id: issue_id} do
      result = Writer.update_status(issue_id, :blocked, reason: "Waiting for API key")
      assert {:ok, _} = result

      {:ok, show_output} = CLI.execute_td(["show", issue_id, "--short"])
      assert show_output =~ "blocked"
    end

    test "starts issue", %{issue_id: issue_id} do
      result = Writer.update_status(issue_id, :start)
      assert {:ok, _} = result
    end
  end

  describe "context parsing" do
    test "parse_done returns list from JSON" do
      handoff = %Handoff{done: Jason.encode!(["Item 1", "Item 2"])}
      assert Handoff.parse_done(handoff) == ["Item 1", "Item 2"]
    end

    test "parse_remaining returns list from JSON" do
      handoff = %Handoff{remaining: Jason.encode!(["Remaining"])}
      assert Handoff.parse_remaining(handoff) == ["Remaining"]
    end

    test "parse_uncertain returns list from JSON" do
      handoff = %Handoff{uncertain: Jason.encode!(["Uncertain"])}
      assert Handoff.parse_uncertain(handoff) == ["Uncertain"]
    end

    test "parse_decisions returns list from JSON" do
      handoff = %Handoff{decisions: Jason.encode!(["Decision"])}
      assert Handoff.parse_decisions(handoff) == ["Decision"]
    end
  end
end
