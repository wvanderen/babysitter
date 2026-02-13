defmodule Babysitter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BabysitterWeb.Telemetry,
      BabysitterWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Babysitter.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
