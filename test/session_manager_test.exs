defmodule Babysitter.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Babysitter.SessionManager

  setup do
    SessionManager.clear()
    :ok
  end

  defp unique_id(prefix) do
    "#{prefix}-#{:rand.uniform(1_000_000)}"
  end

  describe "create_session/2" do
    test "creates a new session with tmux integration" do
      id = unique_id("test")
      assert {:ok, session} = SessionManager.create_session(id)
      assert session.id == id
      assert session.status == :running
      assert session.tmux_name == "babysitter-#{id}"
    end

    test "allows custom tmux name" do
      id = unique_id("test")
      custom_tmux = "custom-#{:rand.uniform(1_000_000)}"
      assert {:ok, session} = SessionManager.create_session(id, tmux_name: custom_tmux)
      assert session.tmux_name == custom_tmux
    end

    test "returns error for duplicate session id" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)
      assert {:error, :already_exists} = SessionManager.create_session(id)
    end
  end

  describe "get_session/1" do
    test "returns session by id" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)
      assert {:ok, session} = SessionManager.get_session(id)
      assert session.id == id
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} =
               SessionManager.get_session("nonexistent-#{:rand.uniform(1_000_000)}")
    end
  end

  describe "list_sessions/0" do
    test "returns all sessions" do
      id1 = unique_id("test")
      id2 = unique_id("test")
      {:ok, _} = SessionManager.create_session(id1)
      {:ok, _} = SessionManager.create_session(id2)

      sessions = SessionManager.list_sessions()
      ids = Enum.map(sessions, & &1.id)
      assert id1 in ids
      assert id2 in ids
    end
  end

  describe "pause_session/1" do
    test "pauses a running session" do
      id = unique_id("test-pause")
      {:ok, _} = SessionManager.create_session(id)
      assert {:ok, :paused} = SessionManager.pause_session(id)
      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :paused
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.pause_session("nonexistent")
    end

    test "returns error if already paused" do
      id = unique_id("test-pause")
      {:ok, _} = SessionManager.create_session(id)
      {:ok, :paused} = SessionManager.pause_session(id)
      assert {:error, :already_paused} = SessionManager.pause_session(id)
    end
  end

  describe "resume_session/1" do
    test "resumes a paused session" do
      id = unique_id("test-resume")
      {:ok, _} = SessionManager.create_session(id)
      {:ok, :paused} = SessionManager.pause_session(id)
      assert {:ok, :running} = SessionManager.resume_session(id)
      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :running
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.resume_session("nonexistent")
    end

    test "returns error if not paused" do
      id = unique_id("test-resume")
      {:ok, _} = SessionManager.create_session(id)
      assert {:error, :not_paused} = SessionManager.resume_session(id)
    end
  end

  describe "destroy_session/1" do
    test "removes session" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)
      assert :ok = SessionManager.destroy_session(id)
      assert {:error, :not_found} = SessionManager.get_session(id)
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.destroy_session("nonexistent")
    end
  end

  describe "output buffer" do
    test "append_output adds to buffer" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)
      :ok = SessionManager.append_output(id, "First line\n")
      :ok = SessionManager.append_output(id, "Second line\n")
      {:ok, output} = SessionManager.get_output(id)
      assert output == "First line\nSecond line\n"
    end
  end
end
