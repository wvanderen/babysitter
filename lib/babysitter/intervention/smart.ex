defmodule Babysitter.Intervention.Smart do
  @moduledoc """
  LLM-powered smart intervention engine.

  Uses LangGraph service to analyze session state and recommend
  intelligent intervention actions (retry, skip, escalate).

  ## Architecture

  1. Builds a prompt from session context (output, validations, retries)
  2. Sends prompt to LangGraph service for LLM analysis
  3. Parses response to determine action
  4. Falls back to Dumb intervention if LangGraph unavailable

  ## Response Format

  The LLM should respond with a JSON-like structure:

      {
        "action": "retry|skip|escalate|ok",
        "reason": "Explanation of why",
        "context": {"optional": "context for retry"}
      }

  """

  alias Babysitter.Intervention.Dumb
  alias Babysitter.Intervention.Result
  alias Babysitter.LangGraph.Client

  @max_output_lines 100
  @default_timeout_ms 30_000

  @doc """
  Analyze a session and determine if intervention is needed.

  Uses LangGraph for LLM-powered analysis. Falls back to Dumb
  intervention if LangGraph is unavailable.

  ## Options

    * `:use_langgraph` - Whether to use LangGraph (default: true if healthy)
    * `:timeout_ms` - Timeout for LangGraph call (default: 30_000)

  ## Returns

  A `Result.t()` with the appropriate action.

  """
  @spec analyze(map(), keyword()) :: Result.t()
  def analyze(session, opts \\ []) do
    use_langgraph = Keyword.get(opts, :use_langgraph, langgraph_available?())
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_timeout_ms)
    stage_id = Map.get(session, :current_stage)

    if use_langgraph do
      analyze_with_langgraph(session, stage_id, timeout_ms)
    else
      Dumb.check(session)
    end
  end

  defp analyze_with_langgraph(session, stage_id, timeout_ms) do
    prompt = build_prompt(session)

    case call_langgraph(prompt, timeout_ms) do
      {:ok, response} ->
        parse_response(response, stage_id)

      {:error, _reason} ->
        Dumb.check(session)
    end
  end

  @doc """
  Build a prompt for the LLM from session context.

  Includes:
  - Session ID and current stage
  - Retry count
  - Recent output (truncated to #{@max_output_lines} lines)
  - Validation results

  """
  @spec build_prompt(map()) :: String.t()
  def build_prompt(session) do
    session_id = Map.get(session, :id, "unknown")
    current_stage = Map.get(session, :current_stage, "unknown")
    retry_count = get_retry_count(session)
    output = truncate_output(Map.get(session, :output_buffer, ""))
    validations = format_validations(Map.get(session, :validations))

    """
    Analyze this agent session and recommend next steps.

    ## Session Context
    - Session ID: #{session_id}
    - Current Stage: #{current_stage}
    - Retry Count: #{retry_count}

    ## Recent Output
    ```
    #{output}
    ```

    ## Validation Results
    #{validations}

    ## Instructions

    Based on the session state, recommend ONE of these actions:

    1. **ok** - Session is healthy, no intervention needed
    2. **retry** - Transient error, worth trying again with context
    3. **skip** - This stage is not applicable, skip to next
    4. **escalate** - Cannot resolve automatically, needs human

    Respond with JSON format:
    ```json
    {
      "action": "retry|skip|escalate|ok",
      "reason": "Brief explanation",
      "context": {"optional": "context for retry"}
    }
    ```
    """
    |> String.trim()
  end

  @doc """
  Parse the LLM response into a Result.

  Validates the action and extracts reason/context.
  Falls back to escalate if response is unparseable.
  """
  @spec parse_response(map() | nil, String.t() | nil) :: Result.t()
  def parse_response(nil, stage_id) do
    Result.escalate("Failed to parse LLM response", stage_id: stage_id)
  end

  def parse_response(response, stage_id) when is_map(response) do
    action = Map.get(response, "action", "unknown")
    reason = Map.get(response, "reason", "No reason provided")
    context = Map.get(response, "context")

    case normalize_action(action) do
      :ok ->
        Result.ok()

      :retry ->
        Result.retry(reason, context: context, stage_id: stage_id)

      :skip ->
        Result.skip(reason, context: context, stage_id: stage_id)

      :escalate ->
        Result.escalate(reason, context: context, stage_id: stage_id)

      :unknown ->
        Result.escalate("Unknown action from LLM: #{action}",
          context: %{raw_response: response},
          stage_id: stage_id
        )
    end
  end

  def parse_response(_, stage_id) do
    Result.escalate("Invalid response format from LLM", stage_id: stage_id)
  end

  @doc """
  Format validations for the prompt.

  Creates a human-readable summary of validation results.
  """
  @spec format_validations(list(map()) | nil) :: String.t()
  def format_validations(nil), do: "No validations"

  def format_validations([]), do: "No validations"

  def format_validations(validations) when is_list(validations) do
    validations
    |> Enum.map(&format_single_validation/1)
    |> Enum.join("\n")
  end

  def format_validations(_), do: "No validations"

  defp format_single_validation(validation) do
    type = Map.get(validation, :type, "unknown")
    status = Map.get(validation, :status, "unknown")
    output = Map.get(validation, :output, "")

    status_emoji = if status == :pass, do: "✓", else: "✗"

    line = "- [#{status_emoji}] #{type}: #{status}"

    if output != "" and output != nil do
      truncated = String.slice(output, 0, 200)
      line <> "\n  Output: #{truncated}"
    else
      line
    end
  end

  defp normalize_action("ok"), do: :ok
  defp normalize_action("retry"), do: :retry
  defp normalize_action("skip"), do: :skip
  defp normalize_action("escalate"), do: :escalate
  defp normalize_action(_), do: :unknown

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

  defp truncate_output(output) when is_binary(output) do
    lines = String.split(output, "\n")

    if length(lines) > @max_output_lines do
      lines
      |> Enum.take(-@max_output_lines)
      |> Enum.join("\n")
      |> then(&("... (truncated #{length(lines) - @max_output_lines} lines)\n" <> &1))
    else
      output
    end
  end

  defp truncate_output(_), do: ""

  defp langgraph_available? do
    Client.healthy?()
  end

  defp call_langgraph(prompt, timeout_ms) do
    task =
      Task.async(fn ->
        with {:ok, %Tesla.Env{body: %{"thread_id" => thread_id}}} <- Client.create_thread(),
             {:ok, %Tesla.Env{body: %{"run_id" => run_id}}} <-
               Client.create_run(thread_id,
                 assistant_id: "agent",
                 input: %{message: prompt}
               ),
             {:ok, result} <- wait_for_run(thread_id, run_id) do
          {:ok, result}
        end
      end)

    case Task.yield(task, timeout_ms) || Task.shutdown(task) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      nil -> {:error, :timeout}
    end
  end

  defp wait_for_run(thread_id, run_id, attempts \\ 30) do
    if attempts <= 0 do
      {:error, :timeout}
    else
      case Client.get_run_status(thread_id, run_id) do
        {:ok, %Tesla.Env{status: 404}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{body: %{"status" => "completed"}}} ->
          get_run_result(thread_id)

        {:ok, %Tesla.Env{body: %{"status" => "error"}}} ->
          {:error, :run_failed}

        {:ok, %Tesla.Env{body: %{"status" => _}}} ->
          Process.sleep(1000)
          wait_for_run(thread_id, run_id, attempts - 1)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp get_run_result(thread_id) do
    case Client.get_state(thread_id) do
      {:ok, %Tesla.Env{body: state}} ->
        result = extract_result_from_state(state)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_result_from_state(%{"values" => values}) when is_map(values) do
    case Map.get(values, "result") do
      nil -> values
      result -> result
    end
  end

  defp extract_result_from_state(state), do: state
end
