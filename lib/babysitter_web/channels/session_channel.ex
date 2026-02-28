defmodule BabysitterWeb.SessionChannel do
  @moduledoc """
  Phoenix Channel for real-time session events.

  Clients subscribe to session:<session_id> to receive:
  - session:started - when a session begins
  - session:output - output lines from the agent
  - session:stage - stage execution events
  - session:status - status changes (running, paused, stopped)
  - stage:started - when a stage begins (stage_id, type, prompt/command)
  - stage:completed - after execution (status, output, error, duration_ms)
  - stage:transition - when moving between stages (from, to, reason)
  - workflow:progress - summary update (current_stage, completed_count, total_stages, status)

  The channel subscribes to Phoenix PubSub on join and forwards all broadcast
  events to connected WebSocket clients for real-time TUI updates.
  """

  use Phoenix.Channel
  alias Babysitter.Broadcast

  def join("session:" <> session_id, _params, socket) do
    :ok = Broadcast.subscribe(session_id)
    socket = assign(socket, :session_id, session_id)
    {:ok, socket}
  end

  def terminate(_reason, socket) do
    Broadcast.unsubscribe(socket.assigns.session_id)
    :ok
  end

  def handle_in("ping", _payload, socket) do
    {:reply, {:ok, %{pong: System.system_time(:millisecond)}}, socket}
  end

  def handle_info(%{event: event, payload: payload}, socket) do
    push(socket, event, payload)
    {:noreply, socket}
  end
end
