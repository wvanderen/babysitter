defmodule Babysitter.BroadcastTest do
  use ExUnit.Case, async: true

  alias Babysitter.Broadcast

  setup do
    session_id = "broadcast-test-#{:rand.uniform(1_000_000)}"
    {:ok, session_id: session_id}
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribes to session events", %{session_id: session_id} do
      assert :ok = Broadcast.subscribe(session_id)
      assert :ok = Broadcast.unsubscribe(session_id)
    end
  end

  describe "session_started/2" do
    test "broadcasts session:started event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      metadata = %{agent: "claude", workflow: "test"}
      :ok = Broadcast.session_started(session_id, metadata)

      assert_receive %{event: "session:started", payload: payload}
      assert payload.session_id == session_id
      assert payload.metadata == metadata
      assert payload.timestamp != nil
    end
  end

  describe "session_output/2" do
    test "broadcasts session:output event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_output(session_id, "Hello from agent")

      assert_receive %{event: "session:output", payload: payload}
      assert payload.session_id == session_id
      assert payload.output == "Hello from agent"
      assert payload.timestamp != nil
    end
  end

  describe "session_stage/4" do
    test "broadcasts session:stage event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_stage(session_id, :build, :started, %{command: "mix compile"})

      assert_receive %{event: "session:stage", payload: payload}
      assert payload.session_id == session_id
      assert payload.stage_id == :build
      assert payload.event == :started
      assert payload.data.command == "mix compile"
    end

    test "broadcasts stage completion event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_stage(session_id, :test, :completed, %{exit_code: 0})

      assert_receive %{event: "session:stage", payload: payload}
      assert payload.event == :completed
      assert payload.data.exit_code == 0
    end
  end

  describe "session_status/3" do
    test "broadcasts status change event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_status(session_id, :initializing, :running)

      assert_receive %{event: "session:status", payload: payload}
      assert payload.session_id == session_id
      assert payload.from == :initializing
      assert payload.to == :running
    end
  end

  describe "session_escalated/3" do
    test "broadcasts session:escalated event with issue_id and reason", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_escalated(session_id, "td-123", "Max retries exceeded")

      assert_receive %{event: "session:escalated", payload: payload}
      assert payload.session_id == session_id
      assert payload.issue_id == "td-123"
      assert payload.reason == "Max retries exceeded"
      assert payload.timestamp != nil
    end

    test "broadcasts session:escalated event without reason", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_escalated(session_id, "td-456", nil)

      assert_receive %{event: "session:escalated", payload: payload}
      assert payload.session_id == session_id
      assert payload.issue_id == "td-456"
      assert payload.reason == nil
    end
  end

  describe "stage_started/3" do
    test "broadcasts stage:started event with metadata", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok =
        Broadcast.stage_started(session_id, :analyze, %{
          type: :prompt,
          prompt: "Read the codebase"
        })

      assert_receive %{event: "stage:started", payload: payload}
      assert payload.session_id == session_id
      assert payload.stage_id == :analyze
      assert payload.type == :prompt
      assert payload.prompt == "Read the codebase"
      assert payload.timestamp != nil
    end

    test "broadcasts stage:started event for command stage", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok =
        Broadcast.stage_started(session_id, :build, %{
          type: :command,
          command: "mix compile"
        })

      assert_receive %{event: "stage:started", payload: payload}
      assert payload.stage_id == :build
      assert payload.type == :command
      assert payload.command == "mix compile"
    end
  end

  describe "stage_completed/4" do
    test "broadcasts stage:completed event on success", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok =
        Broadcast.stage_completed(session_id, :analyze, :success, %{
          output: "Analysis complete",
          duration_ms: 1500
        })

      assert_receive %{event: "stage:completed", payload: payload}
      assert payload.session_id == session_id
      assert payload.stage_id == :analyze
      assert payload.status == :success
      assert payload.output == "Analysis complete"
      assert payload.duration_ms == 1500
      assert payload.error == nil
    end

    test "broadcasts stage:completed event on failure", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok =
        Broadcast.stage_completed(session_id, :test, :failure, %{
          error: "Tests failed",
          duration_ms: 500
        })

      assert_receive %{event: "stage:completed", payload: payload}
      assert payload.status == :failure
      assert payload.error == "Tests failed"
    end
  end

  describe "stage_transition/4" do
    test "broadcasts stage:transition event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.stage_transition(session_id, :analyze, :implement, "success")

      assert_receive %{event: "stage:transition", payload: payload}
      assert payload.session_id == session_id
      assert payload.from == :analyze
      assert payload.to == :implement
      assert payload.reason == "success"
      assert payload.timestamp != nil
    end

    test "broadcasts stage:transition to completion", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok = Broadcast.stage_transition(session_id, :review, nil, "complete")

      assert_receive %{event: "stage:transition", payload: payload}
      assert payload.from == :review
      assert payload.to == nil
      assert payload.reason == "complete"
    end
  end

  describe "workflow_progress/2" do
    test "broadcasts workflow:progress event", %{session_id: session_id} do
      Broadcast.subscribe(session_id)

      :ok =
        Broadcast.workflow_progress(session_id, %{
          current_stage: :implement,
          completed_count: 2,
          total_stages: 5,
          status: :running
        })

      assert_receive %{event: "workflow:progress", payload: payload}
      assert payload.session_id == session_id
      assert payload.current_stage == :implement
      assert payload.completed_count == 2
      assert payload.total_stages == 5
      assert payload.status == :running
      assert payload.timestamp != nil
    end
  end

  describe "multiple subscribers" do
    test "all subscribers receive events", %{session_id: session_id} do
      parent = self()

      task =
        Task.async(fn ->
          Broadcast.subscribe(session_id)
          send(parent, :subscribed)
          assert_receive %{event: "session:output", payload: _}, 1000
        end)

      receive do
        :subscribed -> :ok
      after
        100 -> flunk("Task did not subscribe in time")
      end

      Broadcast.subscribe(session_id)

      :ok = Broadcast.session_output(session_id, "test")

      assert_receive %{event: "session:output", payload: _}
      Task.await(task)
    end
  end
end
