defmodule BabysitterWeb.SessionChannelTest do
  use BabysitterWeb.ChannelCase, async: true

  alias Babysitter.Broadcast
  alias BabysitterWeb.SessionChannel

  setup do
    session_id = "channel-test-#{:rand.uniform(1_000_000)}"

    {:ok, _, socket} =
      BabysitterWeb.UserSocket
      |> socket("socket_id", %{})
      |> subscribe_and_join(SessionChannel, "session:#{session_id}")

    {:ok, socket: socket, session_id: session_id}
  end

  describe "join/3" do
    test "joins session channel successfully", %{session_id: session_id} do
      assert {:ok, _, _socket} =
               BabysitterWeb.UserSocket
               |> socket("socket_id", %{})
               |> subscribe_and_join(SessionChannel, "session:#{session_id}")
    end

    test "assigns session_id to socket", %{socket: socket, session_id: session_id} do
      assert socket.assigns.session_id == session_id
    end
  end

  describe "handle_in/3" do
    test "handles ping and returns pong", %{socket: socket} do
      ref = push(socket, "ping", %{})
      assert_reply(ref, :ok, %{pong: timestamp})
      assert is_integer(timestamp)
    end
  end

  describe "real-time updates" do
    test "receives session:output broadcast after join", %{session_id: session_id} do
      Broadcast.session_output(session_id, "Hello from agent\n")

      assert_push("session:output", payload)
      assert payload.session_id == session_id
      assert payload.output == "Hello from agent\n"
      assert payload.timestamp != nil
    end

    test "receives session:status broadcast", %{session_id: session_id} do
      Broadcast.session_status(session_id, :running, :paused)

      assert_push("session:status", payload)
      assert payload.session_id == session_id
      assert payload.from == :running
      assert payload.to == :paused
    end

    test "receives stage:started broadcast", %{session_id: session_id} do
      Broadcast.stage_started(session_id, :plan, %{type: :agent, prompt: "Plan the task"})

      assert_push("stage:started", payload)
      assert payload.session_id == session_id
      assert payload.stage_id == :plan
      assert payload.type == :agent
      assert payload.prompt == "Plan the task"
    end

    test "receives stage:completed broadcast", %{session_id: session_id} do
      Broadcast.stage_completed(session_id, :plan, :success, %{output: "Done", duration_ms: 1500})

      assert_push("stage:completed", payload)
      assert payload.session_id == session_id
      assert payload.stage_id == :plan
      assert payload.status == :success
      assert payload.output == "Done"
      assert payload.duration_ms == 1500
    end

    test "receives workflow:progress broadcast", %{session_id: session_id} do
      Broadcast.workflow_progress(session_id, %{
        current_stage: :execute,
        completed_count: 2,
        total_stages: 4,
        status: :running
      })

      assert_push("workflow:progress", payload)
      assert payload.session_id == session_id
      assert payload.current_stage == :execute
      assert payload.completed_count == 2
      assert payload.total_stages == 4
      assert payload.status == :running
    end

    test "does not receive broadcasts from other sessions", %{session_id: _session_id} do
      other_session_id = "other-session-#{:rand.uniform(1_000_000)}"

      Broadcast.session_output(other_session_id, "This should not be received")

      refute_push("session:output", %{})
    end

    test "receives multiple output broadcasts in order", %{session_id: session_id} do
      Broadcast.session_output(session_id, "Line 1\n")
      Broadcast.session_output(session_id, "Line 2\n")
      Broadcast.session_output(session_id, "Line 3\n")

      assert_receive %Phoenix.Socket.Message{
        event: "session:output",
        payload: %{output: "Line 1\n"}
      }

      assert_receive %Phoenix.Socket.Message{
        event: "session:output",
        payload: %{output: "Line 2\n"}
      }

      assert_receive %Phoenix.Socket.Message{
        event: "session:output",
        payload: %{output: "Line 3\n"}
      }
    end
  end
end
