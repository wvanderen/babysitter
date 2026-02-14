defmodule Babysitter.State.PersistenceTest do
  use ExUnit.Case, async: false

  alias Babysitter.State.{Persistence, SessionState, Repo}

  setup do
    Repo.delete_all(SessionState)
    :ok
  end

  describe "save_session/1" do
    test "creates new session state" do
      attrs = %{
        id: "test-session-1",
        status: :running,
        tmux_name: "babysitter-test-session-1",
        started_at: DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second),
        metadata: %{"workflow" => "test"}
      }

      assert {:ok, state} = Persistence.save_session(attrs)
      assert state.id == "test-session-1"
      assert state.status == "running"
      assert state.tmux_name == "babysitter-test-session-1"
    end

    test "updates existing session state" do
      Persistence.save_session(%{id: "test-session-2", status: :running})

      assert {:ok, state} =
               Persistence.save_session(%{id: "test-session-2", status: :paused})

      assert state.status == "paused"
    end

    test "stores output buffer" do
      assert {:ok, _} =
               Persistence.save_session(%{
                 id: "test-session-3",
                 status: :running,
                 output_buffer: "initial output"
               })

      {:ok, state} = Persistence.load_session("test-session-3")
      assert state.output_buffer == "initial output"
    end

    test "stores metadata as map" do
      metadata = %{"key" => "value", "nested" => %{"a" => 1}}

      assert {:ok, _} =
               Persistence.save_session(%{
                 id: "test-session-4",
                 status: :running,
                 metadata: metadata
               })

      {:ok, state} = Persistence.load_session("test-session-4")
      assert state.metadata == metadata
    end
  end

  describe "load_session/1" do
    test "returns error for non-existent session" do
      assert {:error, :not_found} = Persistence.load_session("nonexistent")
    end

    test "loads existing session" do
      Persistence.save_session(%{id: "test-session-5", status: :completed})

      assert {:ok, state} = Persistence.load_session("test-session-5")
      assert state.id == "test-session-5"
      assert state.status == "completed"
    end
  end

  describe "delete_session/1" do
    test "deletes existing session" do
      Persistence.save_session(%{id: "test-session-6", status: :running})

      assert {:ok, _} = Persistence.delete_session("test-session-6")
      assert {:error, :not_found} = Persistence.load_session("test-session-6")
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Persistence.delete_session("nonexistent")
    end
  end

  describe "list_sessions/1" do
    test "lists all sessions" do
      Persistence.save_session(%{id: "test-list-1", status: :running})
      Persistence.save_session(%{id: "test-list-2", status: :paused})

      sessions = Persistence.list_sessions()
      assert length(sessions) == 2
    end

    test "filters by status" do
      Persistence.save_session(%{id: "test-list-3", status: :running})
      Persistence.save_session(%{id: "test-list-4", status: :paused})
      Persistence.save_session(%{id: "test-list-5", status: :running})

      sessions = Persistence.list_sessions(status: "running")
      assert length(sessions) == 2
      assert Enum.all?(sessions, &(&1.status == "running"))
    end
  end

  describe "recoverable_sessions/0" do
    test "returns only recoverable sessions" do
      Persistence.save_session(%{id: "recover-1", status: :running})
      Persistence.save_session(%{id: "recover-2", status: :paused})
      Persistence.save_session(%{id: "recover-3", status: :stopped})
      Persistence.save_session(%{id: "recover-4", status: :completed})

      sessions = Persistence.recoverable_sessions()
      ids = Enum.map(sessions, & &1.id)

      assert "recover-1" in ids
      assert "recover-2" in ids
      refute "recover-3" in ids
      refute "recover-4" in ids
    end
  end

  describe "update_status/2" do
    test "updates session status" do
      Persistence.save_session(%{id: "status-1", status: :running})

      assert {:ok, state} = Persistence.update_status("status-1", "paused")
      assert state.status == "paused"
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Persistence.update_status("nonexistent", "paused")
    end
  end

  describe "append_output/2" do
    test "appends output to buffer" do
      Persistence.save_session(%{id: "output-1", status: :running, output_buffer: "first"})

      assert {:ok, state} = Persistence.append_output("output-1", " second")
      assert state.output_buffer == "first second"
    end

    test "truncates buffer when exceeding max size" do
      Persistence.save_session(%{id: "output-2", status: :running})

      large_output = String.duplicate("x", 150_000)

      {:ok, state} = Persistence.append_output("output-2", large_output)

      assert byte_size(state.output_buffer) == 100_000
    end

    test "returns error for non-existent session" do
      assert {:error, :not_found} = Persistence.append_output("nonexistent", "output")
    end
  end

  describe "exists?/1" do
    test "returns true for existing session" do
      Persistence.save_session(%{id: "exists-1", status: :running})
      assert Persistence.exists?("exists-1")
    end

    test "returns false for non-existent session" do
      refute Persistence.exists?("nonexistent")
    end
  end
end
