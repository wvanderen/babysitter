defmodule Babysitter.TmuxTest do
  use ExUnit.Case, async: true

  alias Babysitter.Tmux

  describe "create_session/2" do
    test "creates a detached session by default" do
      assert :ok = Tmux.create_session("test-session-1")
      assert Tmux.session_exists?("test-session-1")
      assert :ok = Tmux.kill_session("test-session-1")
    end

    test "creates a session with custom shell" do
      assert :ok = Tmux.create_session("test-session-2", shell: "/bin/bash")
      assert Tmux.session_exists?("test-session-2")
      assert :ok = Tmux.kill_session("test-session-2")
    end

    test "returns error for duplicate session name" do
      assert :ok = Tmux.create_session("test-session-3")
      assert {:error, _} = Tmux.create_session("test-session-3")
      assert :ok = Tmux.kill_session("test-session-3")
    end
  end

  describe "kill_session/1" do
    test "kills an existing session" do
      assert :ok = Tmux.create_session("test-session-4")
      assert :ok = Tmux.kill_session("test-session-4")
      refute Tmux.session_exists?("test-session-4")
    end

    test "returns error for nonexistent session" do
      assert {:error, _} = Tmux.kill_session("nonexistent-session-xyz")
    end
  end

  describe "session_exists?/1" do
    test "returns true for existing session" do
      assert :ok = Tmux.create_session("test-session-5")
      assert Tmux.session_exists?("test-session-5")
      assert :ok = Tmux.kill_session("test-session-5")
    end

    test "returns false for nonexistent session" do
      refute Tmux.session_exists?("nonexistent-session-xyz")
    end
  end

  describe "list_sessions/0" do
    test "lists existing sessions" do
      assert :ok = Tmux.create_session("test-session-6")
      assert :ok = Tmux.create_session("test-session-7")

      sessions = Tmux.list_sessions()
      assert "test-session-6" in sessions
      assert "test-session-7" in sessions

      assert :ok = Tmux.kill_session("test-session-6")
      assert :ok = Tmux.kill_session("test-session-7")
    end

    test "returns empty list when no sessions" do
      sessions = Tmux.list_sessions()
      assert is_list(sessions)
    end
  end

  describe "send_keys/3" do
    test "sends keys to a session" do
      assert :ok = Tmux.create_session("test-session-8")
      assert :ok = Tmux.send_keys("test-session-8", "echo hello")
      Process.sleep(100)
      output = Tmux.capture_pane("test-session-8")
      assert output =~ "echo hello"
      assert :ok = Tmux.kill_session("test-session-8")
    end
  end

  describe "capture_pane/2" do
    test "captures pane output" do
      assert :ok = Tmux.create_session("test-session-9")
      assert :ok = Tmux.send_keys("test-session-9", "echo test-output-123")
      Process.sleep(100)
      output = Tmux.capture_pane("test-session-9")
      assert is_binary(output)
      assert :ok = Tmux.kill_session("test-session-9")
    end
  end

  describe "resize_window/2" do
    test "resizes window to specified dimensions" do
      assert :ok = Tmux.create_session("test-session-10")
      assert :ok = Tmux.resize_window("test-session-10", width: 80, height: 24)
      assert :ok = Tmux.kill_session("test-session-10")
    end
  end

  describe "rename_session/2" do
    test "renames an existing session" do
      old_name = "test-session-11-#{:erlang.unique_integer([:positive])}"
      new_name = "#{old_name}-renamed"

      assert :ok = Tmux.create_session(old_name)
      assert :ok = Tmux.rename_session(old_name, new_name)
      refute Tmux.session_exists?(old_name)
      assert Tmux.session_exists?(new_name)
      assert :ok = Tmux.kill_session(new_name)
    end

    test "returns error for nonexistent session" do
      assert {:error, _} = Tmux.rename_session("nonexistent", "new-name")
    end
  end
end
