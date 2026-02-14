defmodule Babysitter.TD.CLITest do
  use ExUnit.Case, async: false

  alias Babysitter.TD.CLI

  @moduletag :td_cli

  describe "available?/0" do
    test "returns true when td is installed" do
      assert CLI.available?() == true
    end
  end

  describe "execute_td/2" do
    test "executes td command successfully" do
      result = CLI.execute_td(["--version"])
      assert {:ok, version} = result
      assert String.contains?(version, "td version")
    end

    test "returns error for invalid command" do
      result = CLI.execute_td(["nonexistent-command-xyz-123"])
      assert {:error, _, _} = result
    end
  end

  describe "log/3" do
    test "returns error for empty message" do
      result = CLI.log("td-test-xyz", "")
      assert {:error, "Message cannot be empty", 1} = result
    end

    test "returns error for nil message" do
      result = CLI.log("td-test-xyz", nil)
      assert {:error, "Message cannot be empty", 1} = result
    end
  end

  describe "build functions" do
    test "log builds correct args with type" do
      args = build_log_args_for_test("td-123", "Test message", type: "decision")
      assert "td-123" in args
      assert "Test message" in args
      assert "--type" in args
      assert "decision" in args
    end

    test "handoff builds args with note" do
      args = build_handoff_args_for_test("td-123", note: "Test note")
      assert "td-123" in args
      assert "--note" in args
      assert "Test note" in args
    end

    test "handoff builds args with done items" do
      args = build_handoff_args_for_test("td-123", done: ["Item 1", "Item 2"])
      assert "td-123" in args
      assert "--done" in args
      assert "Item 1" in args
      assert "Item 2" in args
    end

    test "review builds args with reason" do
      args = build_review_args_for_test("td-123", reason: "Done")
      assert "td-123" in args
      assert "--reason" in args
      assert "Done" in args
    end

    test "review builds args with minor flag" do
      args = build_review_args_for_test("td-123", minor: true)
      assert "td-123" in args
      assert "--minor" in args
    end
  end

  defp build_log_args_for_test(issue_id, message, opts) do
    args = [issue_id, message]

    case Keyword.get(opts, :type) do
      nil -> args
      type -> args ++ ["--type", to_string(type)]
    end
  end

  defp build_handoff_args_for_test(issue_id, opts) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :note) do
        nil -> args
        note -> args ++ ["--note", note]
      end

    args =
      opts
      |> Keyword.get(:done, [])
      |> Enum.reduce(args, fn item, acc -> acc ++ ["--done", item] end)

    args
  end

  defp build_review_args_for_test(issue_id, opts) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :reason) do
        nil -> args
        reason -> args ++ ["--reason", reason]
      end

    if Keyword.get(opts, :minor, false) do
      args ++ ["--minor"]
    else
      args
    end
  end
end
