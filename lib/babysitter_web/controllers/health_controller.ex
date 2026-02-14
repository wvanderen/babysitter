defmodule BabysitterWeb.HealthController do
  use Phoenix.Controller, formats: [:json]

  alias Babysitter.WorkflowStore

  @app_start_time System.system_time(:millisecond)

  def health(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def ready(conn, _params) do
    if WorkflowStore.ready?() do
      json(conn, %{status: "ready"})
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{status: "not_ready"})
    end
  end

  def status(conn, _params) do
    uptime_ms = System.system_time(:millisecond) - @app_start_time
    uptime_seconds = div(uptime_ms, 1000)

    json(conn, %{
      status: "ok",
      workflow_count: WorkflowStore.count(),
      uptime_seconds: uptime_seconds
    })
  end
end
