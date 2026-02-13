defmodule Babysitter.Application do
  @moduledoc """
  Main OTP Application for Babysitter.

  Supervision tree:
  - BabysitterWeb.Telemetry (telemetry and pubsub)
  - Babysitter.SessionManager (GenServer for session state)
  - Babysitter.WorkflowSupervisor (DynamicSupervisor for workflows)
  - BabysitterWeb.Endpoint (Phoenix HTTP/WebSocket)
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BabysitterWeb.Telemetry,
      Babysitter.SessionManager,
      {DynamicSupervisor, strategy: :one_for_one, name: Babysitter.WorkflowSupervisor},
      BabysitterWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Babysitter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
