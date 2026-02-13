defmodule Babysitter.Intervention.Dumb do
  @moduledoc """
  Rules-based intervention engine.

  Checks for common failure patterns and returns appropriate action:
  - Max retries exceeded -> escalate
  - Timeout -> restart with context
  - Validation failure -> retry with error context
  - Stuck too long -> intervene
  """

  alias Babysitter.Intervention.Result
  alias Babysitter.Config

  @default_max_retries 3
  @default_stuck_threshold_minutes 10

  @doc """
  Check if intervention is needed for a session.

  Returns a Result with the appropriate action.
  """
  @spec check(map()) :: Result.t()
  def check(session) do
    checks = [
      &check_max_retries/1,
      &check_timeout/1,
      &check_validation_failure/1,
      &check_stuck/1
    ]

    Enum.find_value(checks, Result.ok(), fn check ->
      case check.(session) do
        %Result{action: :ok} -> nil
        result -> result
      end
    end)
  end

  @doc """
  Check if max retries have been exceeded for the current stage.
  """
  @spec check_max_retries(map()) :: Result.t()
  def check_max_retries(session) do
    retry_count = get_retry_count(session)
    max_retries = get_max_retries(session)

    if retry_count >= max_retries do
      Result.escalate("Max retries exceeded",
        context: %{
          retry_count: retry_count,
          max_retries: max_retries,
          stage_id: session.current_stage
        },
        stage_id: session.current_stage
      )
    else
      Result.ok()
    end
  end

  @doc """
  Check if the session has timed out.
  """
  @spec check_timeout(map()) :: Result.t()
  def check_timeout(session) do
    if session.status == :timeout do
      Result.restart("Session timed out",
        context: %{
          last_output: get_last_output(session),
          duration_ms: get_session_duration(session)
        },
        stage_id: session.current_stage
      )
    else
      Result.ok()
    end
  end

  @doc """
  Check if there was a validation failure.
  """
  @spec check_validation_failure(map()) :: Result.t()
  def check_validation_failure(session) do
    case get_last_validation(session) do
      nil ->
        Result.ok()

      %{status: :pass} ->
        Result.ok()

      %{status: :fail} = validation ->
        Result.retry("Validation failed",
          context: %{
            validation_type: validation.type,
            error_output: validation.output,
            exit_code: validation.exit_code
          },
          stage_id: session.current_stage
        )

      %{status: :error} = validation ->
        Result.retry("Validation error",
          context: %{
            validation_type: validation.type,
            error: validation.error
          },
          stage_id: session.current_stage
        )
    end
  end

  @doc """
  Check if the session has been stuck (no progress) for too long.
  """
  @spec check_stuck(map()) :: Result.t()
  def check_stuck(session) do
    stuck_duration = get_stuck_duration(session)
    threshold = get_stuck_threshold(session)

    if stuck_duration && stuck_duration >= threshold do
      Result.escalate("No progress for #{format_duration(stuck_duration)}",
        context: %{
          stuck_duration_ms: stuck_duration,
          threshold_ms: threshold,
          last_output: get_last_output(session)
        },
        stage_id: session.current_stage
      )
    else
      Result.ok()
    end
  end

  defp get_retry_count(session) do
    case Map.get(session, :retries) do
      nil ->
        0

      retries when is_map(retries) ->
        stage_id = Map.get(session, :current_stage)
        Map.get(retries, stage_id, 0)

      _ ->
        0
    end
  end

  defp get_max_retries(session) do
    case Map.get(session, :max_retries) do
      nil -> get_config_max_retries()
      count when is_integer(count) -> count
      _ -> @default_max_retries
    end
  end

  defp get_config_max_retries do
    case Config.intervention() do
      %{max_retries: count} when is_integer(count) -> count
      _ -> @default_max_retries
    end
  end

  defp get_last_output(session) do
    case Map.get(session, :output_buffer) do
      nil -> ""
      buffer when is_binary(buffer) -> buffer
      buffer when is_list(buffer) -> Enum.join(buffer, "\n")
      _ -> ""
    end
  end

  defp get_session_duration(session) do
    case {Map.get(session, :started_at), Map.get(session, :last_activity)} do
      {nil, _} ->
        nil

      {_, nil} ->
        nil

      {started, last} ->
        DateTime.diff(last, started, :millisecond)
    end
  end

  defp get_last_validation(session) do
    case Map.get(session, :validations) do
      nil -> nil
      [] -> nil
      validations when is_list(validations) -> List.last(validations)
      _ -> nil
    end
  end

  defp get_stuck_duration(session) do
    case {Map.get(session, :last_activity), Map.get(session, :last_progress)} do
      {nil, _} ->
        nil

      {last_activity, nil} ->
        DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)

      {last_activity, last_progress} ->
        DateTime.diff(last_activity, last_progress, :millisecond)
    end
  end

  defp get_stuck_threshold(session) do
    case Map.get(session, :stuck_threshold_minutes) do
      nil -> get_config_stuck_threshold()
      minutes when is_integer(minutes) -> minutes * 60_000
      _ -> @default_stuck_threshold_minutes * 60_000
    end
  end

  defp get_config_stuck_threshold do
    case Config.intervention() do
      %{stuck_threshold_minutes: minutes} when is_integer(minutes) ->
        minutes * 60_000

      _ ->
        @default_stuck_threshold_minutes * 60_000
    end
  end

  defp format_duration(ms) do
    minutes = div(ms, 60_000)

    if minutes > 0 do
      "#{minutes} minutes"
    else
      seconds = div(ms, 1_000)
      "#{seconds} seconds"
    end
  end
end
