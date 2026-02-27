defmodule Babysitter.SessionRecovery do
  @moduledoc """
  Handles recovery of session state after daemon restart.

  On startup, this module:
  1. Loads recoverable sessions from SQLite (not stopped/completed)
  2. Checks if corresponding tmux sessions still exist
  3. Restarts Session GenServers for valid recoveries
  4. Marks sessions as failed when tmux is gone
  """

  alias Babysitter.{Session, SessionManager, Tmux}
  alias Babysitter.State.Persistence

  @doc """
  Recover all sessions that can be recovered.

  Returns {:ok, recovered_sessions} where recovered_sessions is a list of
  successfully recovered session states.
  """
  @spec recover_sessions() :: {:ok, [map()]}
  def recover_sessions do
    recovered =
      Persistence.recoverable_sessions()
      |> Enum.map(&recover_session/1)
      |> Enum.filter(&(&1 != nil))

    {:ok, recovered}
  end

  defp recover_session(%{id: id, tmux_name: tmux_name} = persisted_state) do
    if Tmux.session_exists?(tmux_name) do
      recover_with_tmux(id, persisted_state)
    else
      mark_as_failed(id, tmux_name)
      nil
    end
  end

  defp recover_with_tmux(id, persisted_state) do
    case Session.start_recovery(id, build_recovery_opts(persisted_state)) do
      {:ok, _pid} ->
        {:ok, session} = SessionManager.get_session(id)
        session
    end
  end

  defp build_recovery_opts(state) do
    status = String.to_existing_atom(state.status)

    [
      tmux_name: state.tmux_name,
      status: status,
      started_at: state.started_at,
      output_buffer: state.output_buffer,
      metadata: state.metadata,
      failure_reason: state.failure_reason,
      escalation_reason: state.escalation_reason,
      validation_results: state.validation_results
    ]
  end

  defp mark_as_failed(id, tmux_name) do
    Persistence.save_session(%{
      id: id,
      status: :failed,
      failure_reason: "tmux session not found: #{tmux_name}"
    })
  end
end
