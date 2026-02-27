defmodule Babysitter.SessionRecoveryWorker do
  @moduledoc """
  GenServer that recovers persisted sessions on daemon startup.

  This worker runs once at startup to:
  1. Load recoverable sessions from SQLite
  2. Check if tmux sessions still exist
  3. Restart Session GenServers for valid recoveries
  """

  use GenServer

  alias Babysitter.SessionRecovery

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    case SessionRecovery.recover_sessions() do
      {:ok, []} ->
        :ok

      {:ok, recovered} ->
        ids = Enum.map(recovered, & &1.id)
        IO.puts("[SessionRecovery] Recovered #{length(recovered)} sessions: #{inspect(ids)}")
    end

    {:ok, %{recovered: false}}
  end
end
