defmodule Babysitter.Transition do
  @moduledoc """
  Defines a transition between stages.

  Transitions determine the flow from one stage to another
  based on conditions.
  """

  @type condition ::
          :always
          | :success
          | :failure
          | :timeout
          | {:output_contains, String.t()}
          | {:output_matches, String.t() | Regex.t()}
          | {:exit_code, non_neg_integer()}
          | (String.t(), non_neg_integer() -> boolean())

  @type t :: %__MODULE__{
          to_stage: Babysitter.Stage.stage_id(),
          condition: condition(),
          priority: non_neg_integer()
        }

  @enforce_keys [:to_stage]
  defstruct [
    :to_stage,
    :condition,
    priority: 0
  ]

  @doc """
  Create an unconditional transition.
  """
  @spec always(Babysitter.Stage.stage_id()) :: t()
  def always(to_stage) do
    %__MODULE__{to_stage: to_stage, condition: :always}
  end

  @doc """
  Create a success transition.
  """
  @spec on_success(Babysitter.Stage.stage_id()) :: t()
  def on_success(to_stage) do
    %__MODULE__{to_stage: to_stage, condition: :success}
  end

  @doc """
  Create a failure transition.
  """
  @spec on_failure(Babysitter.Stage.stage_id()) :: t()
  def on_failure(to_stage) do
    %__MODULE__{to_stage: to_stage, condition: :failure}
  end

  @doc """
  Create a timeout transition.
  """
  @spec on_timeout(Babysitter.Stage.stage_id()) :: t()
  def on_timeout(to_stage) do
    %__MODULE__{to_stage: to_stage, condition: :timeout}
  end

  @doc """
  Create a transition when output contains a string.
  """
  @spec when_output_contains(Babysitter.Stage.stage_id(), String.t()) :: t()
  def when_output_contains(to_stage, pattern) do
    %__MODULE__{to_stage: to_stage, condition: {:output_contains, pattern}}
  end

  @doc """
  Create a transition when output matches a regex.
  """
  @spec when_output_matches(Babysitter.Stage.stage_id(), String.t() | Regex.t()) :: t()
  def when_output_matches(to_stage, pattern) do
    %__MODULE__{to_stage: to_stage, condition: {:output_matches, pattern}}
  end

  @doc """
  Create a transition when exit code matches.
  """
  @spec when_exit_code(Babysitter.Stage.stage_id(), non_neg_integer()) :: t()
  def when_exit_code(to_stage, code) do
    %__MODULE__{to_stage: to_stage, condition: {:exit_code, code}}
  end

  @doc """
  Create a custom conditional transition.
  """
  @spec when_custom(Babysitter.Stage.stage_id(), function()) :: t()
  def when_custom(to_stage, func) when is_function(func, 2) do
    %__MODULE__{to_stage: to_stage, condition: func}
  end

  @doc """
  Check if this transition should be taken based on execution result.
  """
  @spec matches?(t(), :success | :failure | :timeout, String.t(), non_neg_integer()) :: boolean()
  def matches?(%__MODULE__{condition: :always}, _status, _output, _exit_code), do: true

  def matches?(%__MODULE__{condition: :success}, :success, _output, _exit_code), do: true
  def matches?(%__MODULE__{condition: :failure}, :failure, _output, _exit_code), do: true
  def matches?(%__MODULE__{condition: :timeout}, :timeout, _output, _exit_code), do: true

  def matches?(%__MODULE__{condition: {:output_contains, pattern}}, _status, output, _exit_code) do
    String.contains?(output, pattern)
  end

  def matches?(%__MODULE__{condition: {:output_matches, pattern}}, _status, output, _exit_code) do
    regex = if is_binary(pattern), do: Regex.compile!(pattern), else: pattern
    Regex.match?(regex, output)
  end

  def matches?(%__MODULE__{condition: {:exit_code, code}}, _status, _output, exit_code) do
    exit_code == code
  end

  def matches?(%__MODULE__{condition: func}, _status, output, exit_code)
      when is_function(func, 2) do
    func.(output, exit_code)
  end

  def matches?(%__MODULE__{}, _status, _output, _exit_code), do: false
end
