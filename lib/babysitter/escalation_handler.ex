defmodule Babysitter.EscalationHandler do
  @moduledoc """
  Handles escalation of sessions to human intervention.

  When a session is escalated:
  1. Creates a handoff for the associated issue via TD.CLI
  2. Marks the issue as blocked via TD.CLI
  3. Broadcasts escalation event via WebSocket
  """

  alias Babysitter.Broadcast
  alias Babysitter.TD.CLI

  @type session_id :: String.t()
  @type issue_id :: String.t()

  @type escalation_result ::
          {:ok, :escalated}
          | {:error, :td_unavailable}
          | {:error, {:handoff_failed, String.t()}}
          | {:error, {:block_failed, String.t()}}

  @doc """
  Escalate a session to human intervention.

  Creates a handoff, blocks the issue, and broadcasts the escalation.

  ## Options
    * `:issue_id` - The TD issue ID associated with this session
    * `:reason` - Reason for escalation
    * `:work_dir` - Working directory for td commands
    * `:handoff_note` - Note to include in the handoff
    * `:done` - List of completed items for handoff
    * `:remaining` - List of remaining items for handoff
  """
  @spec escalate(session_id(), keyword()) :: escalation_result()
  def escalate(session_id, opts) do
    issue_id = Keyword.get(opts, :issue_id)
    reason = Keyword.get(opts, :reason)
    work_dir = Keyword.get(opts, :work_dir)

    with :ok <- ensure_td_available(),
         :ok <- create_handoff(issue_id, opts),
         :ok <- block_issue(issue_id, reason, work_dir) do
      Broadcast.session_escalated(session_id, issue_id, reason)
      {:ok, :escalated}
    end
  end

  @doc """
  Check if escalation is needed based on intervention result.
  """
  @spec should_escalate?(map()) :: boolean()
  def should_escalate?(%{action: :escalate}), do: true
  def should_escalate?(_), do: false

  defp ensure_td_available do
    if CLI.available?() do
      :ok
    else
      {:error, :td_unavailable}
    end
  end

  defp create_handoff(nil, _opts), do: :ok

  defp create_handoff(issue_id, opts) do
    work_dir = Keyword.get(opts, :work_dir)
    handoff_opts = build_handoff_opts(opts)

    case CLI.handoff(issue_id, Keyword.put(handoff_opts, :work_dir, work_dir)) do
      {:ok, _} -> :ok
      {:error, message, _code} -> {:error, {:handoff_failed, message}}
    end
  end

  defp build_handoff_opts(opts) do
    []
    |> maybe_add_opt(opts, :note, :handoff_note)
    |> maybe_add_opt(opts, :done, :done)
    |> maybe_add_opt(opts, :remaining, :remaining)
  end

  defp maybe_add_opt(acc, source_opts, target_key, source_key) do
    case Keyword.get(source_opts, source_key) do
      nil -> acc
      value -> Keyword.put(acc, target_key, value)
    end
  end

  defp block_issue(nil, _reason, _work_dir), do: :ok

  defp block_issue(issue_id, reason, work_dir) do
    opts = [reason: reason || "Session escalated - requires human intervention"]

    opts =
      if work_dir do
        Keyword.put(opts, :work_dir, work_dir)
      else
        opts
      end

    case CLI.block(issue_id, opts) do
      {:ok, _} -> :ok
      {:error, message, _code} -> {:error, {:block_failed, message}}
    end
  end
end
