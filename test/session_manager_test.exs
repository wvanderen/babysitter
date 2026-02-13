defmodule Babysitter.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Babysitter.SessionManager

  setup do
    SessionManager.clear()
    :ok
  end

  describe "create_session/2" do
    test "creates a new session with tmux integration" do
      assert {:ok, session} = SessionManager.create_session("test-1")
      assert session.id == "test-1"
      assert session.status == :running
      assert session.tmux_name == "babysitter-test-1"
    end

    test "allows custom tmux name" do
      assert {:ok, session} = SessionManager.create_session("test-2", tmux_name: "custom-name")
      assert session.tmux_name == "custom-name"
    end
  end

  describe "get_session/1" do
    test "returns session by id" do
      {:ok, _} = SessionManager.create_session("test-4")
      assert {:ok, session} = SessionManager.get_session("test-4")
      assert session.id == "test-4"
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.get_session("nonexistent")
    end
  end

  describe "list_sessions/0" do
    test "returns all sessions" do
      {:ok, _} = SessionManager.create_session("test-5")
      {:ok, _} = SessionManager.create_session("test-6")

      sessions = SessionManager.list_sessions()
      ids = Enum.map(sessions, & &1.id)
      assert "test-5" in ids
      assert "test-6" in ids
    end
  end

  describe "pause_session/1" do
    test "pauses a running session" do
      {:ok, _} = SessionManager.create_session("test-pause")
      assert {:ok, session} = SessionManager.pause_session("test-pause")
      assert session.status == :paused
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.pause_session("nonexistent")
    end

    test "returns error if already paused" do
      {:ok, _} = SessionManager.create_session("test-pause-2")
      {:ok, _} = SessionManager.pause_session("test-pause-2")
      assert {:error, :already_paused} = SessionManager.pause_session("test-pause-2")
    end
  end

  describe "resume_session/1" do
    test "resumes a paused session" do
      {:ok, _} = SessionManager.create_session("test-resume")
      {:ok, _} = SessionManager.pause_session("test-resume")
      assert {:ok, session} = SessionManager.resume_session("test-resume")
      assert session.status == :running
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.resume_session("nonexistent")
    end

    test "returns error if not paused" do
      {:ok, _} = SessionManager.create_session("test-resume-2")
      assert {:error, :not_paused} = SessionManager.resume_session("test-resume-2")
    end
  end

  describe "destroy_session/1" do
    test "removes session" do
      {:ok, _} = SessionManager.create_session("test-7")
      assert :ok = SessionManager.destroy_session("test-7")
      assert {:error, :not_found} = SessionManager.get_session("test-7")
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.destroy_session("nonexistent")
    end
  end
end
