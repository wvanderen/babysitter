defmodule Babysitter.StuckDetection do
  @moduledoc """
  Stuck detection heuristics for identifying no-progress scenarios.

  Analyzes output patterns and timing to detect when an agent is stuck:
  - Repetitive output (same lines/commands repeating)
  - Error loops (same error appearing multiple times)
  - No-progress timeout (no meaningful output for extended period)
  - Output rate stall (dramatic decrease in output rate)
  - Infinite loop indicators (specific patterns)
  """

  defmodule Detection do
    @type severity :: :none | :low | :medium | :high | :critical
    @type reason ::
            :none
            | :repetitive_output
            | :command_loop
            | :error_loop
            | :no_progress
            | :output_stall
            | :infinite_loop

    @type t :: %__MODULE__{
            stuck: boolean(),
            severity: severity(),
            reason: reason(),
            details: map(),
            confidence: float()
          }

    @enforce_keys [:stuck]
    defstruct [:stuck, :severity, :reason, :details, :confidence]

    @spec none() :: t()
    def none, do: %__MODULE__{stuck: false, severity: :none, reason: :none, confidence: 1.0}

    @spec detected(severity(), reason(), map(), float()) :: t()
    def detected(severity, reason, details, confidence) do
      %__MODULE__{
        stuck: true,
        severity: severity,
        reason: reason,
        details: details,
        confidence: confidence
      }
    end

    @spec stuck?(t()) :: boolean()
    def stuck?(%__MODULE__{stuck: true}), do: true
    def stuck?(%__MODULE__{}), do: false

    @spec needs_intervention?(t()) :: boolean()
    def needs_intervention?(%__MODULE__{severity: severity})
        when severity in [:medium, :high, :critical],
        do: true

    def needs_intervention?(%__MODULE__{}), do: false
  end

  alias Babysitter.StuckDetection.Detection
  alias Babysitter.OutputParser

  @default_config %{
    repetition_threshold: 3,
    command_loop_threshold: 3,
    error_loop_threshold: 2,
    no_progress_timeout_ms: 300_000,
    output_stall_threshold: 0.1,
    min_lines_for_analysis: 10,
    analysis_window_lines: 100
  }

  @infinite_loop_patterns [
    ~r/^\s*while\s*\(true\)/i,
    ~r/^\s*for\s*\(\s*;\s*;\s*\)/,
    ~r/^\s*while\s*\(\s*1\s*\)/i,
    ~r/\bwhile\s+True:/i,
    ~r/\bloop\s*\{/i,
    ~r/\bfor\s+_?\s*in\s+range\s*\(\s*\d+\s*\.\.\s*$/,
    ~r/infinite.?loop/i
  ]

  @command_patterns [
    ~r/^\$\s+(.+)$/,
    ~r/^>\s+(.+)$/,
    ~r/^Running:\s+(.+)$/,
    ~r/^Executing:\s+(.+)$/,
    ~r/^\[\d+\]\s+(.+)$/
  ]

  @spec analyze(String.t(), map(), keyword()) :: Detection.t()
  def analyze(output, context \\ %{}, opts \\ [])

  def analyze(output, context, opts) when is_binary(output) do
    config = build_config(opts)
    context = context || %{}
    history = Map.get(context, :history)
    last_activity = Map.get(context, :last_activity)

    checks = [
      {:high, &check_infinite_loop_patterns/2},
      {:high, &check_error_loop/2},
      {:medium, &check_command_loop/2},
      {:medium, &check_repetitive_output/2},
      {:low, &check_output_stall/2},
      {:low, &check_no_progress_timeout/2}
    ]

    context_with_extras =
      context
      |> Map.put(:history, history)
      |> Map.put(:last_activity, last_activity)
      |> Map.put(:config, config)

    Enum.find_value(checks, Detection.none(), fn {severity, check_fn} ->
      case check_fn.(output, context_with_extras) do
        nil -> nil
        {reason, details, confidence} -> Detection.detected(severity, reason, details, confidence)
      end
    end)
  end

  def analyze(_, _, _), do: Detection.none()

  @spec stuck?(String.t(), map(), keyword()) :: boolean()
  def stuck?(output, context \\ %{}, opts \\ []) do
    output
    |> analyze(context, opts)
    |> Detection.stuck?()
  end

  @spec needs_intervention?(String.t(), map(), keyword()) :: boolean()
  def needs_intervention?(output, context \\ %{}, opts \\ []) do
    output
    |> analyze(context, opts)
    |> Detection.needs_intervention?()
  end

  defp check_infinite_loop_patterns(output, _context) do
    lines = String.split(output, "\n")

    matches =
      Enum.flat_map(lines, fn line ->
        Enum.filter(@infinite_loop_patterns, &Regex.match?(&1, line))
      end)

    if Enum.any?(matches) do
      {
        :infinite_loop,
        %{matched_patterns: Enum.map(matches, &Regex.source/1), count: length(matches)},
        0.90
      }
    else
      nil
    end
  end

  defp check_error_loop(output, context) do
    config = Map.get(context, :config, @default_config)
    threshold = Map.get(config, :error_loop_threshold, 2)

    error_signals =
      output
      |> OutputParser.parse([])
      |> Map.get(:signals, [])
      |> Enum.filter(&(&1.type == :error))

    if length(error_signals) >= threshold do
      unique_errors =
        error_signals
        |> Enum.map(& &1.matched)
        |> Enum.uniq()

      {
        :error_loop,
        %{
          error_count: length(error_signals),
          unique_errors: length(unique_errors),
          errors: Enum.take(Enum.map(error_signals, & &1.matched), 5)
        },
        min(0.95, 0.70 + length(error_signals) * 0.05)
      }
    else
      nil
    end
  end

  defp check_command_loop(output, context) do
    config = Map.get(context, :config, @default_config)
    threshold = Map.get(config, :command_loop_threshold, 3)

    commands = extract_commands(output)

    if length(commands) >= threshold do
      command_counts = Enum.frequencies(commands)
      {most_common, count} = Enum.max_by(command_counts, fn {_k, v} -> v end, fn -> {nil, 0} end)

      if count >= threshold do
        {
          :command_loop,
          %{
            command: most_common,
            repeat_count: count,
            total_commands: length(commands)
          },
          min(0.90, 0.60 + count * 0.10)
        }
      else
        nil
      end
    else
      nil
    end
  end

  defp check_repetitive_output(output, context) do
    config = Map.get(context, :config, @default_config)
    threshold = Map.get(config, :repetition_threshold, 3)
    window = Map.get(config, :analysis_window_lines, 100)

    lines =
      output
      |> String.split("\n")
      |> Enum.take(-window)
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))

    if length(lines) < Map.get(config, :min_lines_for_analysis, 10) do
      nil
    else
      line_counts = Enum.frequencies(lines)
      {most_common, count} = Enum.max_by(line_counts, fn {_k, v} -> v end, fn -> {nil, 0} end)

      if count >= threshold and most_common != nil do
        {
          :repetitive_output,
          %{
            repeated_line: String.slice(most_common, 0, 100),
            repeat_count: count,
            unique_lines: map_size(line_counts),
            total_lines: length(lines)
          },
          min(0.85, 0.55 + count * 0.10)
        }
      else
        nil
      end
    end
  end

  defp check_output_stall(output, context) do
    config = Map.get(context, :config, @default_config)
    history = Map.get(context, :history)

    if is_nil(history) or not is_binary(history) do
      nil
    else
      stall_threshold = Map.get(config, :output_stall_threshold, 0.1)

      current_size = byte_size(output)
      history_size = byte_size(history)
      time_diff_s = Map.get(context, :time_diff_s, 60)

      if history_size > 0 and time_diff_s > 0 do
        current_rate = current_size / time_diff_s
        history_rate = history_size / 60

        if history_rate > 0 and current_rate / history_rate < stall_threshold do
          {
            :output_stall,
            %{
              current_rate_bps: round(current_rate),
              previous_rate_bps: round(history_rate),
              rate_ratio: Float.round(current_rate / history_rate, 2)
            },
            0.70
          }
        else
          nil
        end
      else
        nil
      end
    end
  end

  defp check_no_progress_timeout(_output, context) do
    config = Map.get(context, :config, @default_config)
    last_activity = Map.get(context, :last_activity)
    timeout_ms = Map.get(config, :no_progress_timeout_ms, 300_000)

    if is_nil(last_activity) do
      nil
    else
      now = DateTime.utc_now()

      case DateTime.diff(now, last_activity, :millisecond) do
        elapsed when elapsed >= timeout_ms ->
          {
            :no_progress,
            %{
              elapsed_ms: elapsed,
              threshold_ms: timeout_ms,
              last_activity: DateTime.to_iso8601(last_activity)
            },
            0.80
          }

        _ ->
          nil
      end
    end
  end

  defp extract_commands(output) do
    lines = String.split(output, "\n")

    Enum.flat_map(lines, fn line ->
      result =
        Enum.find_value(@command_patterns, fn pattern ->
          case Regex.run(pattern, line) do
            [_, command] -> [String.trim(command)]
            _ -> nil
          end
        end)

      result || []
    end)
  end

  defp build_config(opts) do
    override = Keyword.get(opts, :config, %{})
    Map.merge(@default_config, override)
  end
end
