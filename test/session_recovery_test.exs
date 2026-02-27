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

  describe "Task 4.1: session persistence round-trip" do
    test "full round-trip: create session, persist, simulate restart, recover" do
      id = unique_id("roundtrip")
      tmux_name = "babysitter-#{id}"

      {:ok, _pid} =
        SessionManager.create_session(id,
          tmux_name: tmux_name,
          command: "sleep 60"
        )

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :running

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: session.started_at |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
      })

      {:ok, persisted} = Persistence.load_session(id)
      assert persisted.id == id
      assert persisted.status == "running"
      assert persisted.tmux_name == tmux_name

      pid = GenServer.whereis({:via, Registry, {Babysitter.SessionRegistry, id}})
      DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
      :timer.sleep(50)

      refute match?({:ok, _}, SessionManager.get_session(id))

      {:ok, recovered} = SessionRecovery.recover_sessions()
      assert id in Enum.map(recovered, & &1.id)

      {:ok, restored} = SessionManager.get_session(id)
      assert restored.status == :running
      assert restored.tmux_name == tmux_name

      SessionManager.destroy_session(id)
    end

    test "round-trip preserves all session state fields" do
      id = unique_id("fullstate")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      started_at = ~N[2026-02-26 10:00:00]
      metadata = %{"workflow_id" => "wf-123", "stage" => "execution"}
      output_buffer = "line1\nline2\nline3\n"

      Persistence.save_session(%{
        id: id,
        status: :paused,
        tmux_name: tmux_name,
        started_at: started_at,
        output_buffer: output_buffer,
        metadata: metadata,
        failure_reason: nil,
        escalation_reason: nil
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :paused
      assert session.tmux_name == tmux_name
      assert session.output_buffer == output_buffer
      assert session.metadata == metadata

      {:ok, persisted} = Persistence.load_session(id)
      assert persisted.started_at == started_at

      SessionManager.destroy_session(id)
    end
  end

  describe "Task 4.2: tmux session survival simulation" do
    test "tmux session persists through daemon restart simulation" do
      id = unique_id("tmux-survive")
      tmux_name = "babysitter-#{id}"

      {:ok, _} =
        SessionManager.create_session(id,
          tmux_name: tmux_name,
          command: "sleep 60"
        )

      assert Babysitter.Tmux.session_exists?(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      pid = GenServer.whereis({:via, Registry, {Babysitter.SessionRegistry, id}})
      DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
      :timer.sleep(50)

      assert Babysitter.Tmux.session_exists?(tmux_name),
             "tmux session should survive daemon restart"

      {:ok, recovered} = SessionRecovery.recover_sessions()
      assert id in Enum.map(recovered, & &1.id)

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :running

      SessionManager.destroy_session(id)
    end

    test "handles partial tmux state (some sessions gone)" do
      id_alive = unique_id("alive")
      id_dead = unique_id("dead")
      tmux_alive = "babysitter-#{id_alive}"
      tmux_dead = "babysitter-#{id_dead}"

      Babysitter.Tmux.create_session(tmux_alive)

      Persistence.save_session(%{
        id: id_alive,
        status: :running,
        tmux_name: tmux_alive,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      Persistence.save_session(%{
        id: id_dead,
        status: :running,
        tmux_name: tmux_dead,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      {:ok, recovered} = SessionRecovery.recover_sessions()

      assert id_alive in Enum.map(recovered, & &1.id)
      refute id_dead in Enum.map(recovered, & &1.id)

      {:ok, dead_state} = Persistence.load_session(id_dead)
      assert dead_state.status == "failed"
      assert dead_state.failure_reason =~ "tmux session not found"

      SessionManager.destroy_session(id_alive)
    end

    test "recovers session with persisted output buffer" do
      id = unique_id("output-persist")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      output_buffer = "line1\nline2\nline3\n"

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        output_buffer: output_buffer
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, output_after} = Session.get_output(id)
      assert output_after =~ "line"

      SessionManager.destroy_session(id)
    end
  end

  describe "Task 4.3: workflow resume after simulated crash" do
    test "workflow state survives crash and resumes" do
      id = unique_id("workflow-crash")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      workflow_metadata = %{
        "workflow_id" => "wf-crash-test",
        "current_stage" => "execution",
        "variables" => %{"target" => "production", "dry_run" => false},
        "retry_count" => 1,
        "execution_history" => ["setup", "validate"]
      }

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        metadata: workflow_metadata
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.metadata["workflow_id"] == "wf-crash-test"
      assert session.metadata["current_stage"] == "execution"
      assert session.metadata["variables"]["target"] == "production"
      assert session.metadata["retry_count"] == 1
      assert "setup" in session.metadata["execution_history"]

      SessionManager.destroy_session(id)
    end

    test "escalated session recovers with escalation context" do
      id = unique_id("escalated-crash")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :escalated,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        escalation_reason: "Validation failed: missing required field",
        metadata: %{
          "failed_stage" => "validate",
          "error_details" => "field 'name' is required"
        }
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :escalated
      assert session.escalation_reason == "Validation failed: missing required field"
      assert session.metadata["failed_stage"] == "validate"

      SessionManager.destroy_session(id)
    end

    test "paused session resumes from paused state" do
      id = unique_id("paused-crash")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :paused,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive(),
        metadata: %{"pause_reason" => "awaiting user input"}
      })

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session} = SessionManager.get_session(id)
      assert session.status == :paused
      assert session.metadata["pause_reason"] == "awaiting user input"

      SessionManager.destroy_session(id)
    end
  end

  describe "Task 4.4: LangGraph mapping persistence through recovery" do
    alias Babysitter.State.LangGraphSession

    setup do
      Repo.delete_all(LangGraphSession)
      :ok
    end

    test "LangGraph thread_id persists through daemon restart" do
      id = unique_id("lg-thread")
      tmux_name = "babysitter-#{id}"

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      Persistence.save_langgraph_session(%{
        session_id: id,
        thread_id: "thread-persist-test",
        checkpoint_id: "cp-initial"
      })

      Babysitter.Tmux.create_session(tmux_name)

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session_after} = SessionManager.get_session(id)
      assert session_after.langgraph_thread_id == "thread-persist-test"

      mapping = Persistence.get_langgraph_session(id)
      assert mapping.thread_id == "thread-persist-test"

      SessionManager.destroy_session(id)
    end

    test "LangGraph checkpoint_id persists through daemon restart" do
      id = unique_id("lg-checkpoint")
      tmux_name = "babysitter-#{id}"

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      Persistence.save_langgraph_session(%{
        session_id: id,
        thread_id: "thread-checkpoint-test",
        checkpoint_id: "cp-v1-initial"
      })

      Babysitter.Tmux.create_session(tmux_name)

      {:ok, _} = SessionRecovery.recover_sessions()

      {:ok, session_after} = SessionManager.get_session(id)
      assert session_after.langgraph_checkpoint_id == "cp-v1-initial"

      SessionManager.destroy_session(id)
    end

    test "LangGraph mapping survives multiple restart cycles" do
      id = unique_id("lg-multi")
      tmux_name = "babysitter-#{id}"

      Babysitter.Tmux.create_session(tmux_name)

      Persistence.save_session(%{
        id: id,
        status: :running,
        tmux_name: tmux_name,
        started_at: DateTime.utc_now() |> DateTime.to_naive()
      })

      Persistence.save_langgraph_session(%{
        session_id: id,
        thread_id: "thread-multi-cycle",
        checkpoint_id: "cp-cycle-1"
      })

      for cycle <- 1..3 do
        {:ok, _} = SessionRecovery.recover_sessions()

        {:ok, session} = SessionManager.get_session(id)
        assert session.langgraph_thread_id == "thread-multi-cycle"

        new_checkpoint = "cp-cycle-#{cycle + 1}"
        :ok = Session.update_langgraph_checkpoint(id, new_checkpoint)

        pid = GenServer.whereis({:via, Registry, {Babysitter.SessionRegistry, id}})
        DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
        :timer.sleep(50)
      end

      {:ok, _} = SessionRecovery.recover_sessions()
      {:ok, final_session} = SessionManager.get_session(id)
      assert final_session.langgraph_checkpoint_id == "cp-cycle-4"

      SessionManager.destroy_session(id)
    end

    test "session without LangGraph mapping recovers gracefully" do
      id = unique_id("no-lg")
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
      assert session.langgraph_thread_id == nil
      assert session.langgraph_checkpoint_id == nil

      SessionManager.destroy_session(id)
    end
  end
end
