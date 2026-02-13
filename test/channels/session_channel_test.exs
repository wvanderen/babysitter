defmodule BabysitterWeb.SessionChannelTest do
  use BabysitterWeb.ChannelCase, async: true

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
end
