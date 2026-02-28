defmodule Babysitter.Agent.Completion do
  @moduledoc """
  Detects when agents have completed their tasks.

  Uses a two-tier detection strategy:
  1. Primary: Look for explicit completion marker in output (e.g., BABYSITTER_DONE)
  2. Secondary: Detect output stability (no changes for configurable threshold)

  This replaces the fragile stability-only detection with explicit markers
  while maintaining stability as a fallback for agents without markers.
  """

  alias Babysitter.{Config, Tmux}

  @default_timeout 300_000
  @default_stability_threshold 10_000
  @poll_interval 500

  @doc """
  Check if output indicates completion.

  ## Options

    * `:marker` - Completion marker pattern (string or regex). Empty/nil disables marker detection.
    * `:stability_threshold` - Milliseconds of output stability required (default: 10_000)
    * `:last_output` - Previous output for stability comparison
    * `:stable_ms` - Current stability duration in milliseconds

  ## Returns

    * `{:ok, :complete}` - Completion marker found
    * `{:ok, :stable}` - Output is stable (no changes for threshold duration)
    * `{:continue, reason}` - Not yet complete, with reason atom

  ## Examples

      iex> Babysitter.Agent.Completion.check("Done\\nBABYSITTER_DONE\\n", marker: "BABYSITTER_DONE")
      {:ok, :complete}

      iex> Babysitter.Agent.Completion.check("Working...", marker: "BABYSITTER_DONE")
      {:continue, :marker_not_found}
  """
  @spec check(String.t(), keyword()) :: {:ok, :complete | :stable} | {:continue, atom()}
  def check(output, opts \\ [])

  def check(output, opts) when is_binary(output) do
    marker = Keyword.get(opts, :marker)
    stability_threshold = Keyword.get(opts, :stability_threshold, @default_stability_threshold)
    last_output = Keyword.get(opts, :last_output)
    stable_ms = Keyword.get(opts, :stable_ms, 0)

    marker_result = check_marker(output, marker)
    stability_result = check_stability(output, last_output, stable_ms, stability_threshold)
    combine_results(marker_result, stability_result)
  end

  defp check_marker(_output, nil), do: {:marker_disabled, true}
  defp check_marker(_output, ""), do: {:marker_disabled, true}

  defp check_marker(output, marker) when is_binary(marker) do
    case Regex.run(~r/#{marker}/, output) do
      [_ | _] -> {:complete, false}
      nil -> {:marker_not_found, true}
    end
  end

  defp check_stability(output, last_output, stable_ms, threshold) do
    normalized = normalize_for_stability(output)
    last_normalized = if last_output, do: normalize_for_stability(last_output), else: nil

    new_stable_ms =
      if normalized == last_normalized do
        stable_ms + @poll_interval
      else
        0
      end

    if new_stable_ms >= threshold do
      {:ok, :stable}
    else
      {:continue, :unstable}
    end
  end

  defp combine_results({:complete, _}, _stability_result), do: {:ok, :complete}
  defp combine_results({:marker_not_found, _}, {:ok, :stable}), do: {:ok, :stable}
  defp combine_results({:marker_not_found, _}, {:continue, _}), do: {:continue, :marker_not_found}
  defp combine_results({:marker_disabled, _}, stability_result), do: stability_result

  @doc """
  Wait for agent completion by polling tmux output.

  ## Options

    * `:marker` - Completion marker pattern (string or regex)
    * `:stability_threshold` - Milliseconds of stability required (default: 10_000)
    * `:timeout` - Maximum wait time in milliseconds (default: 300_000)

  ## Returns

    * `{:ok, output}` - Completion detected with final output
    * `{:error, :timeout}` - Timed out waiting for completion

  ## Examples

      iex> Babysitter.Agent.Completion.wait_for_completion("session-1", marker: "BABYSITTER_DONE", timeout: 5000)
      {:ok, "Task output\\nBABYSITTER_DONE\\n"}
  """
  @spec wait_for_completion(String.t(), keyword()) :: {:ok, String.t()} | {:error, :timeout}
  def wait_for_completion(tmux_name, opts \\ []) do
    marker = Keyword.get(opts, :marker)
    stability_threshold = Keyword.get(opts, :stability_threshold, @default_stability_threshold)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for_completion(tmux_name, marker, stability_threshold, deadline, nil, 0)
  end

  defp do_wait_for_completion(
         tmux_name,
         marker,
         stability_threshold,
         deadline,
         last_output,
         stable_ms
       ) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      Process.sleep(@poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          case check(output,
                 marker: marker,
                 stability_threshold: stability_threshold,
                 last_output: last_output,
                 stable_ms: stable_ms
               ) do
            {:ok, _} ->
              {:ok, output}

            {:continue, _} ->
              do_wait_for_completion(
                tmux_name,
                marker,
                stability_threshold,
                deadline,
                output,
                calculate_stable_ms(output, last_output, stable_ms)
              )
          end

        {:error, _} ->
          do_wait_for_completion(
            tmux_name,
            marker,
            stability_threshold,
            deadline,
            last_output,
            stable_ms
          )
      end
    end
  end

  @doc """
  Normalize output for stability comparison.

  Strips ANSI codes, box drawing characters, and trims whitespace.

  ## Examples

      iex> Babysitter.Agent.Completion.normalize_for_stability("\\e[32mColored\\e[0m")
      "Colored"

      iex> Babysitter.Agent.Completion.normalize_for_stability("  text  ")
      "text"
  """
  @spec normalize_for_stability(String.t()) :: String.t()
  def normalize_for_stability(output) when is_binary(output) do
    output
    |> strip_ansi_codes()
    |> strip_box_drawing()
    |> String.trim()
  end

  defp strip_ansi_codes(output) do
    Regex.replace(~r/\x1b\[[0-9;]*[a-zA-Z]/, output, "")
  end

  defp strip_box_drawing(output) do
    output
    |> String.replace(~r/[─│┌┐└┘├┤┬┴┼╭╮╯╰╱╲╳]/, "")
    |> String.replace(~r/[▀▄█▓▒░]/, "")
    |> String.replace(~r/[►◄▲▼]/, "")
  end

  @doc """
  Get completion configuration for an agent.

  Returns a map with:
    * `:marker` - Completion marker pattern (or nil)
    * `:stability_threshold` - Stability threshold in ms
    * `:timeout` - Completion timeout in ms

  ## Examples

      iex> Babysitter.Agent.Completion.config_for_agent(:pi)
      %{marker: nil, stability_threshold: 10_000, timeout: 300_000}
  """
  @spec config_for_agent(atom()) :: map()
  def config_for_agent(agent_name) when is_atom(agent_name) do
    agent_config = Config.agent(agent_name) || %{}

    %{
      marker: Map.get(agent_config, :completion_pattern),
      stability_threshold:
        Map.get(agent_config, :stability_threshold, @default_stability_threshold),
      timeout: Map.get(agent_config, :completion_timeout, @default_timeout)
    }
  end

  @doc """
  Get the default timeout value.

  ## Examples

      iex> Babysitter.Agent.Completion.default_timeout()
      300_000
  """
  @spec default_timeout() :: non_neg_integer()
  def default_timeout, do: @default_timeout

  @doc """
  Get the default stability threshold.

  ## Examples

      iex> Babysitter.Agent.Completion.default_stability_threshold()
      10_000
  """
  @spec default_stability_threshold() :: non_neg_integer()
  def default_stability_threshold, do: @default_stability_threshold

  @doc """
  Calculate new stability duration based on output change.

  ## Parameters

    * `output` - Current output
    * `:last_output` - Previous output
    * `:stable_ms` - Current stability duration in milliseconds

  ## Returns

  New stability duration in milliseconds.

  ## Examples

      iex> Babysitter.Agent.Completion.calculate_stable_ms("same", "same", 1000)
      1500

      iex> Babysitter.Agent.Completion.calculate_stable_ms("new", "old", 1000)
      0
  """
  @spec calculate_stable_ms(String.t(), String.t() | nil, non_neg_integer()) :: non_neg_integer()
  def calculate_stable_ms(output, last_output, stable_ms) when is_binary(output) do
    normalized = normalize_for_stability(output)
    last_normalized = if last_output, do: normalize_for_stability(last_output), else: nil

    if normalized == last_normalized do
      stable_ms + @poll_interval
    else
      0
    end
  end
end
