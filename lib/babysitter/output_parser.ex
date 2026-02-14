defmodule Babysitter.OutputParser do
  @moduledoc "Parses agent output for completion signals, errors, progress markers."

  @completion_patterns [
    ~r/^Commit created:/mi,
    ~r/^Changes committed/mi,
    ~r/\[SUCCESS\]/i,
    ~r/^Done[:.]/mi,
    ~r/^Completed[:.]/mi,
    ~r/^Finished[:.]/mi,
    ~r/^All tests passing/mi,
    ~r/^Build succeeded/mi,
    ~r/^Successfully /mi,
    ~r/^(Task|Operation) complete/mi,
    ~r/^Ready for review/mi,
    ~r/^No (more )?changes needed/mi,
    ~r/\bexit code: 0\b/i
  ]

  @error_patterns [
    ~r/^Error[:.]/mi,
    ~r/^Exception[:.]/mi,
    ~r/^FATAL[:.]/mi,
    ~r/^CRITICAL[:.]/mi,
    ~r/^FAILED[:.]/mi,
    ~r/stack trace:/mi,
    ~r/Traceback \(most recent/mi,
    ~r/\*\*\* ERROR \*\*\*/mi,
    ~r/\[ERROR\]/mi,
    ~r/exited with (?:code|status):\s*[1-9]/mi,
    ~r/\bexit code: [1-9]\d*\b/i,
    ~r/^panic:/mi,
    ~r/^thread '\w+' panicked/mi,
    ~r/Segmentation fault/mi,
    ~r/Built target.*FAILED/mi,
    ~r/E: Unable to locate package/mi,
    ~r/npm ERR!/mi,
    ~r/yarn error/mi
  ]

  @input_patterns [
    ~r/^Enter (?:your )?password[:：]\s*$/mi,
    ~r/^Username[:：]\s*$/mi,
    ~r/^Email[:：]\s*$/mi,
    ~r/^\?\s+Enter\s+/mi,
    ~r/^\?\s+Select\s+/mi,
    ~r/^\?\s+Choose\s+/mi,
    ~r/\[Y\/n\]/i,
    ~r/\[y\/N\]/i,
    ~r/\(yes\/no\)/i,
    ~r/Press (?:Enter|any key)/i,
    ~r/Please (?:enter|input|type|provide)/mi,
    ~r/^Password:\s*$/m,
    ~r/^Username:\s*$/m,
    ~r/2FA code:/i,
    ~r/verification code:/i,
    ~r/OTP:/i,
    ~r/confirmation code:/i
  ]

  @progress_patterns [
    ~r/Thinking[.。]+/i,
    ~r/Processing[.。]+/i,
    ~r/Analyzing[.。]+/i,
    ~r/^Reading\s+/mi,
    ~r/^Writing\s+/mi,
    ~r/^Creating\s+/mi,
    ~r/^Updating\s+/mi,
    ~r/^Deleting\s+/mi,
    ~r/^Modifying\s+/mi,
    ~r/^Running\s+/mi,
    ~r/^Executing\s+/mi,
    ~r/^Building\s+/mi,
    ~r/^Compiling\s+/mi,
    ~r/^Downloading\s+/mi,
    ~r/^Uploading\s+/mi,
    ~r/^Installing\s+/mi,
    ~r/^Generating\s+/mi,
    ~r/\b\d+%\s*(?:complete|done|progress)/i,
    ~r/\[\d+%?\]/,
    ~r/\(\d+\/\d+\)/,
    ~r/Writing file:/mi,
    ~r/Editing file:/mi,
    ~r/^Working on:/mi,
    ~r/^Attempting:/mi,
    ~r/^Trying:/mi
  ]

  @stuck_threshold_lines 50
  @stuck_similarity_threshold 0.95

  @spec parse(String.t(), keyword()) :: map()
  def parse(output, opts \\ [])

  def parse(output, opts) when is_binary(output) do
    history = Keyword.get(opts, :history)
    stuck_threshold = Keyword.get(opts, :stuck_threshold_lines, @stuck_threshold_lines)
    stuck_similarity = Keyword.get(opts, :stuck_similarity, @stuck_similarity_threshold)
    completion_signals = detect_signals(output, @completion_patterns, :completion)
    error_signals = detect_signals(output, @error_patterns, :error)
    input_signals = detect_signals(output, @input_patterns, :input_required)
    progress_signals = detect_signals(output, @progress_patterns, :progress)
    all_signals = completion_signals ++ error_signals ++ input_signals ++ progress_signals
    status = determine_status(output, all_signals, history, stuck_threshold, stuck_similarity)
    errors = extract_errors(output, error_signals)
    progress = extract_progress(output, progress_signals)
    confidence = calculate_confidence(status, all_signals, output)

    %{
      status: status,
      signals: all_signals,
      errors: errors,
      progress: progress,
      confidence: confidence
    }
  end

  def parse(_, _opts),
    do: %{status: :in_progress, signals: [], errors: [], progress: [], confidence: 0.0}

  @spec completed?(String.t()) :: boolean()
  def completed?(output) when is_binary(output),
    do: detect_signals(output, @completion_patterns, :completion) != []

  def completed?(_), do: false

  @spec has_error?(String.t()) :: boolean()
  def has_error?(output) when is_binary(output),
    do: detect_signals(output, @error_patterns, :error) != []

  def has_error?(_), do: false

  @spec needs_input?(String.t()) :: boolean()
  def needs_input?(output) when is_binary(output),
    do: detect_signals(output, @input_patterns, :input_required) != []

  def needs_input?(_), do: false

  @spec stuck?(String.t(), String.t() | nil, keyword()) :: boolean()
  def stuck?(output, history, opts \\ [])
  def stuck?(output, nil, _opts) when is_binary(output), do: false

  def stuck?(output, history, opts) when is_binary(output) and is_binary(history) do
    threshold = Keyword.get(opts, :threshold, @stuck_similarity_threshold)
    lines = Keyword.get(opts, :lines, @stuck_threshold_lines)
    recent_output = tail_output(output, lines)
    recent_history = tail_output(history, lines)

    if byte_size(recent_output) == 0 or byte_size(recent_history) == 0,
      do: false,
      else: calculate_similarity(recent_output, recent_history) >= threshold
  end

  def stuck?(_, _, _), do: false

  @spec extract_errors(String.t(), list() | nil) :: [String.t()]
  def extract_errors(output, signals \\ nil)

  def extract_errors(output, nil) when is_binary(output),
    do: extract_errors(output, detect_signals(output, @error_patterns, :error))

  def extract_errors(output, signals) when is_binary(output) and is_list(signals) do
    lines = String.split(output, "\n")

    Enum.map(signals, fn signal ->
      line_num = signal.line
      context_start = max(0, line_num - 1)
      context_end = min(length(lines), line_num + 5)
      lines |> Enum.slice(context_start..(context_end - 1)) |> Enum.join("\n")
    end)
  end

  def extract_errors(_, _), do: []

  @spec extract_progress(String.t(), list() | nil) :: [String.t()]
  def extract_progress(output, signals \\ nil)

  def extract_progress(output, nil) when is_binary(output),
    do: extract_progress(output, detect_signals(output, @progress_patterns, :progress))

  def extract_progress(output, signals) when is_binary(output) and is_list(signals) do
    lines = String.split(output, "\n")

    signals
    |> Enum.map(fn signal -> Enum.at(lines, signal.line) || "" end)
    |> Enum.filter(&(&1 != ""))
  end

  def extract_progress(_, _), do: []

  @spec tail_output(String.t(), non_neg_integer()) :: String.t()
  def tail_output(output, lines \\ 50)

  def tail_output(output, lines) when is_binary(output) and is_integer(lines) and lines > 0 do
    output |> String.split("\n") |> Enum.take(-lines) |> Enum.join("\n")
  end

  def tail_output(_, _), do: ""

  @spec has_progress?(String.t()) :: boolean()
  def has_progress?(output) when is_binary(output),
    do: detect_signals(output, @progress_patterns, :progress) != []

  def has_progress?(_), do: false

  defp detect_signals(output, patterns, type) when is_binary(output) do
    lines = String.split(output, "\n")

    patterns
    |> Enum.flat_map(fn pattern ->
      lines
      |> Enum.with_index()
      |> Enum.filter(fn {line, _idx} -> Regex.match?(pattern, line) end)
      |> Enum.map(fn {line, idx} ->
        %{
          type: type,
          pattern: Regex.source(pattern),
          matched: String.slice(line, 0, 100),
          line: idx
        }
      end)
    end)
  end

  defp determine_status(output, signals, history, stuck_threshold, stuck_similarity) do
    has_completion = Enum.any?(signals, &(&1.type == :completion))
    has_error = Enum.any?(signals, &(&1.type == :error))
    has_input = Enum.any?(signals, &(&1.type == :input_required))

    cond do
      has_error and has_completion ->
        :completed

      has_input ->
        :needs_input

      has_error ->
        :error

      has_completion ->
        :completed

      stuck?(output, history, stuck_threshold: stuck_threshold, threshold: stuck_similarity) ->
        :stuck

      true ->
        :in_progress
    end
  end

  defp calculate_similarity(a, b) when is_binary(a) and is_binary(b) do
    a_words = a |> String.downcase() |> String.split(~r/\s+/) |> MapSet.new()
    b_words = b |> String.downcase() |> String.split(~r/\s+/) |> MapSet.new()

    if MapSet.size(a_words) == 0 or MapSet.size(b_words) == 0,
      do: 0.0,
      else:
        MapSet.size(MapSet.intersection(a_words, b_words)) /
          MapSet.size(MapSet.union(a_words, b_words))
  end

  defp calculate_similarity(_, _), do: 0.0

  defp calculate_confidence(:completed, signals, output) do
    completion_count = Enum.count(signals, &(&1.type == :completion))
    has_multiple = completion_count > 1
    output_length = String.length(output)

    cond do
      has_multiple and output_length > 100 -> 0.95
      has_multiple -> 0.85
      output_length > 500 -> 0.90
      output_length > 100 -> 0.80
      true -> 0.70
    end
  end

  defp calculate_confidence(:error, signals, output) do
    error_count = Enum.count(signals, &(&1.type == :error))
    if error_count > 1 or String.contains?(output, "stack trace"), do: 0.95, else: 0.80
  end

  defp calculate_confidence(:needs_input, signals, _output) do
    input_count = Enum.count(signals, &(&1.type == :input_required))
    if input_count > 1, do: 0.90, else: 0.85
  end

  defp calculate_confidence(:stuck, _, _), do: 0.75

  defp calculate_confidence(:in_progress, signals, _output) do
    progress_count = Enum.count(signals, &(&1.type == :progress))
    min(0.50 + progress_count * 0.05, 0.70)
  end
end
