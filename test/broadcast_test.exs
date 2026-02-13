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
