defmodule Babysitter.Broadcast do
  @moduledoc """
  Broadcasts session events via Phoenix PubSub.

  Events are broadcast to "session:<session_id>" topic.
  """

  alias Phoenix.PubSub

  @pubsub Babysitter.PubSub

  @type session_id :: String.t()

  @doc """
  Broadcast session started event.
  """
  @spec session_started(session_id(), map()) :: :ok
  def session_started(session_id, metadata \\ %{}) do
    broadcast(session_id, "session:started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: metadata
    })
  end

  @doc """
  Broadcast output from session.
  """
  @spec session_output(session_id(), String.t()) :: :ok
  def session_output(session_id, output) do
    broadcast(session_id, "session:output", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      output: output
    })
  end

  @doc """
  Broadcast stage execution event.
  """
  @spec session_stage(session_id(), atom(), atom(), map()) :: :ok
  def session_stage(session_id, stage_id, event, data \\ %{}) do
    broadcast(session_id, "session:stage", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      stage_id: stage_id,
      event: event,
      data: data
    })
  end

  @doc """
  Broadcast status change event.
  """
  @spec session_status(session_id(), atom(), atom()) :: :ok
  def session_status(session_id, from_status, to_status) do
    broadcast(session_id, "session:status", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      from: from_status,
      to: to_status
    })
  end

  @doc """
  Broadcast escalation event with issue context.
  """
  @spec session_escalated(session_id(), String.t(), String.t() | nil) :: :ok
  def session_escalated(session_id, issue_id, reason \\ nil) do
    broadcast(session_id, "session:escalated", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      issue_id: issue_id,
      reason: reason
    })
  end

  @doc """
  Broadcast stage started event.
  """
  @spec stage_started(session_id(), atom(), map()) :: :ok
  def stage_started(session_id, stage_id, metadata \\ %{}) do
    broadcast(session_id, "stage:started", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      stage_id: stage_id,
      type: Map.get(metadata, :type),
      prompt: Map.get(metadata, :prompt),
      command: Map.get(metadata, :command)
    })
  end

  @doc """
  Broadcast stage completed event.
  """
  @spec stage_completed(session_id(), atom(), atom(), map()) :: :ok
  def stage_completed(session_id, stage_id, status, result \\ %{}) do
    broadcast(session_id, "stage:completed", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      stage_id: stage_id,
      status: status,
      output: Map.get(result, :output),
      error: Map.get(result, :error),
      duration_ms: Map.get(result, :duration_ms)
    })
  end

  @doc """
  Broadcast stage transition event.
  """
  @spec stage_transition(session_id(), atom() | nil, atom() | nil, String.t() | nil) :: :ok
  def stage_transition(session_id, from_stage, to_stage, reason \\ nil) do
    broadcast(session_id, "stage:transition", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      from: from_stage,
      to: to_stage,
      reason: reason
    })
  end

  @doc """
  Broadcast workflow progress event.
  """
  @spec workflow_progress(session_id(), map()) :: :ok
  def workflow_progress(session_id, progress) do
    broadcast(session_id, "workflow:progress", %{
      session_id: session_id,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      current_stage: Map.get(progress, :current_stage),
      completed_count: Map.get(progress, :completed_count),
      total_stages: Map.get(progress, :total_stages),
      status: Map.get(progress, :status)
    })
  end

  @doc """
  Subscribe to all events for a session.
  """
  @spec subscribe(session_id()) :: :ok | {:error, term()}
  def subscribe(session_id) do
    PubSub.subscribe(@pubsub, topic(session_id))
  end

  @doc """
  Unsubscribe from session events.
  """
  @spec unsubscribe(session_id()) :: :ok
  def unsubscribe(session_id) do
    PubSub.unsubscribe(@pubsub, topic(session_id))
  end

  defp broadcast(session_id, event, payload) do
    PubSub.broadcast(@pubsub, topic(session_id), %{event: event, payload: payload})
    :ok
  end

  defp topic(session_id), do: "session:#{session_id}"
end
