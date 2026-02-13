defmodule BabysitterWeb.SessionChannel do
  @moduledoc """
  Phoenix Channel for real-time session events.

  Clients subscribe to session:<session_id> to receive:
  - session:started - when a session begins
  - session:output - output lines from the agent
  - session:stage - stage execution events
  - session:status - status changes (running, paused, stopped)
  """

  use Phoenix.Channel

  def join("session:" <> session_id, _params, socket) do
    socket = assign(socket, :session_id, session_id)
    {:ok, socket}
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: System.system_time(:millisecond)}}, socket}
  end
end
