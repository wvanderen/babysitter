defmodule Babysitter.SetupWorker do
  @moduledoc """
  Startup worker that verifies dependencies and creates required directories.

  This module runs during application startup to:
  - Verify tmux is available
  - Create required runtime directories

  If tmux is not available, the application will fail to start with a clear error.
  """

  use GenServer

  require Logger

  @doc """
  Starts the setup worker.

  The worker performs setup synchronously in `init/1`, causing the application
  to fail to start if setup fails.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    with :ok <- verify_tmux(),
         :ok <- ensure_directories() do
      Logger.info("Babysitter setup complete: tmux verified, directories created")
      {:ok, %{}}
    end
  end

  defp verify_tmux do
    case Babysitter.Tmux.Verifier.verify_tmux_available() do
      {:ok, version} ->
        Logger.info("tmux #{version} found")
        :ok

      {:error, :tmux_not_found} ->
        {:error, Babysitter.Tmux.Verifier.installation_instructions()}
    end
  end

  defp ensure_directories do
    Babysitter.Setup.ensure_directories!()
    :ok
  end
end
