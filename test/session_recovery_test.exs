defmodule Babysitter.SessionRecoveryTest do
  use ExUnit.Case, async: false

  alias Babysitter.{Session, SessionManager, SessionRecovery, SessionRecoveryWorker}
  alias Babysitter.State.{Persistence, SessionState, Repo}

  setup do
    Repo.delete_all(SessionState)
    SessionManager.clear()
    :ok
  end

  defp unique_id(prefix) do
    "#{prefix}-#{:rand.uniform(1_000_000)}"
  end

  describe "recover_sessions/0" do
    test "returns empty list when no sessions to recover" do
      assert {:ok, []} = SessionRecovery.recover_sessions()
    end

    test "recovers session with existing tmux" do
      id = unique_id("recover")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        metadata: %{"workflow" => "test"}
      })

      assert {:ok, recovered} = SessionRecovery.recover_sessions()
      assert id in Enum.map(recovered, & &1.id)

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :running
      assert session.tmux_name == tmux_name

      SessionManager.destroy_session(id)
    end

    test "marks session as failed when tmux is gone" do
      id = unique_id("recover")
      tmux_name = "babysitter-nonexistent-#{:rand.uniform(1_000_000)}"

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      assert {:ok, []} = SessionRecovery.recover_sessions()

      {:ok, state} = Persistence.load_session(id)
      assert state.status == "failed"
      assert state.failure_reason =~ "tmux session not found"
    end

    test "skips already stopped sessions" do
      id = unique_id("stopped")
      Persistence.save_session(%{id: id, status: :stopped})

      assert {:ok, []} = SessionRecovery.recover_sessions()
    end

    test "skips completed sessions" do
      id = unique_id("completed")
      Persistence.save_session(%{id: id, status: :completed})

      assert {:ok, []} = SessionRecovery.recover_sessions()
    end

    test "recovers paused session" do
      id = unique_id("paused")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :paused,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      assert {:ok, recovered} = SessionRecovery.recover_sessions()
      assert id in Enum.map(recovered, & &1.id)

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :paused

      SessionManager.destroy_session(id)
    end

    test "recovers escalated session" do
      id = unique_id("escalated")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :escalated,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        escalation_reason: "needs review"
      })

      assert {:ok, _recovered} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :escalated
      assert session.escalation_reason == "needs review"

      SessionManager.destroy_session(id)
    end

    test "recovers multiple sessions" do
      id1 = unique_id("multi1")
      id2 = unique_id("multi2")
      tmux1 = "babysitter-#{id1}"
      tmux2 = "babysitter-#{id2}"

      Babysitter.Tmux.create_session(tmux1)
      Babysitter.Tmux.create_session(tmux2)

      Persistence.save_session(%{
        id: id1,
        status: :running,
        tmux_name: tmux1,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      Persistence.save_session(%{
        id: id2,
        status: :running,
        tmux_name: tmux2,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      assert {:ok, recovered} = SessionRecovery.recover_sessions()
      assert length(recovered) == 2

      SessionManager.destroy_session(id1)
      SessionManager.destroy_session(id2)
    end

    test "restores output buffer from persistence" do
      id = unique_id("buffer")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        output_buffer: "previous output\n"
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, output} = Session.get_output(id)
      assert output == "previous output\n"

      SessionManager.destroy_session(id)
    end
  end

  describe "Session recovery mode" do
    test "start_recovery/1 creates session attached to existing tmux" do
      id = unique_id("recovery")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      assert {:ok, pid} = Session.start_recovery(id, tmux_name: tmux_name)
      assert is_pid(pid)

      {:ok, state} = Session.get_state(id)
      assert state.status == :running
      assert state.tmux_name == tmux_name

      Session.stop(id)
      DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
    end

    test "start_recovery/1 fails when tmux does not exist" do
      id = unique_id("recovery")

      assert {:error, {:tmux_not_found, _}} =
               Session.start_recovery(id,
                 tmux_name: "nonexistent-tmux-#{:rand.uniform(1_000_000)}"
               )
    end

    test "start_recovery/1 restores state from persistence" do
      id = unique_id("recovery")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :paused,
        tmux_name: tmux_name,
        started_at: ~N[2026-01-01 12:00:00],
        output_buffer: "saved output",
        metadata: %{"key" => "value"}
      })

      assert {:ok, _pid} = Session.start_recovery(id, tmux_name: tmux_name)

      {:ok, state} = Session.get_state(id)
      assert state.status == :paused
      assert state.output_buffer == "saved output"
      assert state.metadata == %{"key" => "value"}

      Session.stop(id)
    end
  end

  describe "SessionRecoveryWorker" do
    test "worker is started as part of application supervision tree" do
      assert Process.whereis(SessionRecoveryWorker) != nil
    end

    test "SessionRecovery.recover_sessions can be called directly" do
      id = unique_id("direct")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :running

      SessionManager.destroy_session(id)
    end
  end
end
