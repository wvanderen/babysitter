defmodule Babysitter.Agent.ReadyTest do
  use ExUnit.Case, async: true

  alias Babysitter.Agent.Ready

  describe "wait_for_ready/3" do
    setup do
      session_name = "test-ready-#{:rand.uniform(1_000_000)}"
      :ok = Babysitter.Tmux.create_session(session_name)
      on_exit(fn -> Babysitter.Tmux.kill_session(session_name) end)
      {:ok, session_name: session_name}
    end

    test "returns {:ok, :ready} when pattern is found in output", %{session_name: session_name} do
      Babysitter.Tmux.send_keys(session_name, "echo 'test> ready'")
      Process.sleep(100)

      assert {:ok, :ready} = Ready.wait_for_ready(session_name, ">", 1000)
    end

    test "returns {:error, :timeout} when pattern not found within timeout", %{
      session_name: session_name
    } do
      assert {:error, :timeout} =
               Ready.wait_for_ready(session_name, "NONEXISTENT_PATTERN_XYZ", 50)
    end

    test "supports multi-character patterns", %{session_name: session_name} do
      Babysitter.Tmux.send_keys(session_name, "echo '❯|> prompt'")
      Process.sleep(100)

      assert {:ok, :ready} = Ready.wait_for_ready(session_name, "❯|>", 1000)
    end

    test "handles empty output gracefully", %{session_name: session_name} do
      assert {:error, :timeout} = Ready.wait_for_ready(session_name, "anything", 50)
    end
  end

  describe "poll_for_pattern/4" do
    test "returns {:ok, match} when pattern found" do
      output = "Some output\n❯|> \nMore output"
      assert {:ok, true} = Ready.poll_for_pattern(output, "❯|>")
    end

    test "returns {:ok, false} when pattern not found" do
      output = "Some output without pattern"
      assert {:ok, false} = Ready.poll_for_pattern(output, "❯|>")
    end

    test "matches at end of output" do
      output = "Starting agent...\nReady> "
      assert {:ok, true} = Ready.poll_for_pattern(output, ">")
    end
  end

  describe "default_timeout/0" do
    test "returns default timeout value" do
      assert Ready.default_timeout() == 30_000
    end
  end
end
