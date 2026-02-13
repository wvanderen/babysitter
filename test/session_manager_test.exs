defmodule Babysitter.SessionManagerTest do
  use ExUnit.Case, async: false

  alias Babysitter.SessionManager

  setup do
    sessions = SessionManager.list_sessions()

    for session <- sessions do
      SessionManager.destroy_session(session.id)
    end

    :ok
  end

  describe "create_session/2" do
    test "creates a new session" do
      assert {:ok, session} = SessionManager.create_session("test-1")
      assert session.id == "test-1"
      assert session.status == :starting
    end

    test "allows multiple sessions" do
      assert {:ok, _} = SessionManager.create_session("test-2")
      assert {:ok, _} = SessionManager.create_session("test-3")
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

  describe "destroy_session/1" do
    test "marks session as stopped" do
      {:ok, _} = SessionManager.create_session("test-7")
      assert {:ok, session} = SessionManager.destroy_session("test-7")
      assert session.status == :stopped
    end

    test "returns error for nonexistent session" do
      assert {:error, :not_found} = SessionManager.destroy_session("nonexistent")
    end
  end
end
