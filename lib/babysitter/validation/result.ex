defmodule Babysitter.Validation.Result do
  @moduledoc """
  Result of a validation check.

  Captures the status, output, timing, and any artifacts
  generated during validation.
  """

  @type validation_type :: :test | :compile | :lint | :command | :custom

  @type status :: :pass | :fail | :error | :skipped

  @type t :: %__MODULE__{
          type: validation_type(),
          status: status(),
          output: String.t(),
          exit_code: non_neg_integer() | nil,
          error: String.t() | nil,
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          duration_ms: non_neg_integer() | nil,
          artifacts: [String.t()]
        }

  @enforce_keys [:type, :status, :started_at, :finished_at]
  defstruct [
    :type,
    :status,
    :started_at,
    :finished_at,
    output: "",
    exit_code: nil,
    error: nil,
    duration_ms: nil,
    artifacts: []
  ]

  @doc """
  Create a passing result.
  """
  @spec pass(validation_type(), String.t(), keyword()) :: t()
  def pass(type, output, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      type: type,
      status: :pass,
      output: output,
      started_at: Keyword.get(opts, :started_at, now),
      finished_at: Keyword.get(opts, :finished_at, now),
      exit_code: Keyword.get(opts, :exit_code, 0),
      artifacts: Keyword.get(opts, :artifacts, [])
    }
  end

  @doc """
  Create a failing result.
  """
  @spec fail(validation_type(), String.t(), keyword()) :: t()
  def fail(type, output, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      type: type,
      status: :fail,
      output: output,
      started_at: Keyword.get(opts, :started_at, now),
      finished_at: Keyword.get(opts, :finished_at, now),
      exit_code: Keyword.get(opts, :exit_code),
      artifacts: Keyword.get(opts, :artifacts, [])
    }
  end

  @doc """
  Create an error result (execution failed, not test failure).
  """
  @spec error(validation_type(), String.t(), keyword()) :: t()
  def error(type, error_message, opts \\ []) do
    now = DateTime.utc_now()

    %__MODULE__{
      type: type,
      status: :error,
      error: error_message,
      started_at: Keyword.get(opts, :started_at, now),
      finished_at: Keyword.get(opts, :finished_at, now),
      output: Keyword.get(opts, :output, "")
    }
  end

  @doc """
  Check if the result is passing.
  """
  @spec pass?(t()) :: boolean()
  def pass?(%__MODULE__{status: :pass}), do: true
  def pass?(%__MODULE__{}), do: false

  @doc """
  Check if the result is failing.
  """
  @spec fail?(t()) :: boolean()
  def fail?(%__MODULE__{status: :fail}), do: true
  def fail?(%__MODULE__{}), do: false

  @doc """
  Get the duration in milliseconds.
  """
  @spec duration(t()) :: non_neg_integer()
  def duration(%__MODULE__{duration_ms: ms}) when is_integer(ms), do: ms

  def duration(%__MODULE__{started_at: started, finished_at: finished}) do
    DateTime.diff(finished, started, :millisecond)
  end

  @doc """
  Extract summary from test output.
  """
  @spec summary(t()) :: String.t()
  def summary(%__MODULE__{status: :pass}), do: "PASSED"
  def summary(%__MODULE__{status: :skipped}), do: "SKIPPED"
  def summary(%__MODULE__{status: :error, error: error}), do: "ERROR: #{error}"

  def summary(%__MODULE__{status: :fail, output: output}) do
    case extract_failure_summary(output) do
      nil -> "FAILED"
      summary -> "FAILED: #{summary}"
    end
  end

  defp extract_failure_summary(output) do
    cond do
      match = Regex.run(~r/(\d+)\s+failures?/i, output) ->
        "#{Enum.at(match, 1)} failures"

      match = Regex.run(~r/(\d+)\s+tests?\s+failed/i, output) ->
        "#{Enum.at(match, 1)} tests failed"

      match = Regex.run(~r/FAIL\s+(.+)$/m, output) ->
        Enum.at(match, 1)

      true ->
        nil
    end
  end
end
