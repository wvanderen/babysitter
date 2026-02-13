defmodule Babysitter.TransitionEngine do
  @moduledoc """
  Evaluates transitions between stages based on execution results.

  Determines which stage to execute next based on:
  - on_success, on_failure, on_timeout shortcuts
  - Transition conditions (output patterns, exit codes, custom functions)
  - Priority ordering of multiple transitions
  """

  alias Babysitter.{Stage, Transition, StageExecutor.Result}

  @type transition_result ::
          {:ok, Stage.stage_id()}
          | {:ok, :complete}
          | {:error, :no_transition_defined}

  @doc """
  Determine the next stage based on execution result.

  First checks explicit transitions (if any), then falls back to
  on_success/on_failure/on_timeout shortcuts.

  ## Returns
    * `{:ok, stage_id}` - Next stage to execute
    * `{:ok, :complete}` - Workflow is complete
    * `{:error, :no_transition_defined}` - No valid transition found
  """
  @spec next_stage(Stage.t(), Result.t()) :: transition_result()
  def next_stage(%Stage{} = stage, %Result{} = result) do
    cond do
      has_explicit_transitions?(stage) ->
        evaluate_transitions(stage.transitions, result)

      has_shortcut_transitions?(stage) ->
        evaluate_shortcut(stage, result)

      true ->
        {:error, :no_transition_defined}
    end
  end

  @doc """
  Check if a stage has any explicit transitions defined.
  """
  @spec has_explicit_transitions?(Stage.t()) :: boolean()
  def has_explicit_transitions?(%Stage{transitions: []}), do: false
  def has_explicit_transitions?(%Stage{transitions: [_ | _]}), do: true

  @doc """
  Check if a stage has shortcut transitions (on_success/on_failure/on_timeout).
  """
  @spec has_shortcut_transitions?(Stage.t()) :: boolean()
  def has_shortcut_transitions?(%Stage{on_success: nil, on_failure: nil, on_timeout: nil}) do
    false
  end

  def has_shortcut_transitions?(%Stage{}), do: true

  @doc """
  Evaluate explicit transitions in priority order.

  Transitions are sorted by priority (higher first) and the first
  matching transition is returned.
  """
  @spec evaluate_transitions([Transition.t()], Result.t()) :: transition_result()
  def evaluate_transitions(transitions, %Result{} = result) do
    sorted =
      transitions
      |> Enum.sort_by(& &1.priority, :desc)

    case find_matching_transition(sorted, result) do
      {:ok, transition} -> {:ok, transition.to_stage}
      :no_match -> {:error, :no_transition_defined}
    end
  end

  @doc """
  Evaluate shortcut transitions based on result status.

  Falls through from timeout -> failure -> success if specific
  handler is not defined.
  """
  @spec evaluate_shortcut(Stage.t(), Result.t()) :: transition_result()
  def evaluate_shortcut(%Stage{} = stage, %Result{status: :timeout}) do
    cond do
      stage.on_timeout != nil -> {:ok, stage.on_timeout}
      stage.on_failure != nil -> {:ok, stage.on_failure}
      stage.on_success != nil -> {:ok, stage.on_success}
      true -> {:error, :no_transition_defined}
    end
  end

  def evaluate_shortcut(%Stage{} = stage, %Result{status: :failure}) do
    cond do
      stage.on_failure != nil -> {:ok, stage.on_failure}
      stage.on_success != nil -> {:ok, stage.on_success}
      true -> {:error, :no_transition_defined}
    end
  end

  def evaluate_shortcut(%Stage{} = stage, %Result{status: :success}) do
    if stage.on_success != nil do
      {:ok, stage.on_success}
    else
      {:error, :no_transition_defined}
    end
  end

  @doc """
  Find the first matching transition for a result.

  Checks each transition's condition against the result.
  """
  @spec find_matching_transition([Transition.t()], Result.t()) ::
          {:ok, Transition.t()} | :no_match
  def find_matching_transition([], _result), do: :no_match

  def find_matching_transition([%Transition{} = t | rest], %Result{} = result) do
    if transition_matches?(t, result) do
      {:ok, t}
    else
      find_matching_transition(rest, result)
    end
  end

  @doc """
  Check if a transition matches an execution result.
  """
  @spec transition_matches?(Transition.t(), Result.t()) :: boolean()
  def transition_matches?(%Transition{condition: :always}, _result), do: true

  def transition_matches?(%Transition{condition: :success}, %Result{status: :success}), do: true

  def transition_matches?(%Transition{condition: :failure}, %Result{status: :failure}),
    do: true

  def transition_matches?(%Transition{condition: :timeout}, %Result{status: :timeout}), do: true

  def transition_matches?(
        %Transition{condition: {:output_contains, pattern}},
        %Result{output: output}
      ) do
    String.contains?(output, pattern)
  end

  def transition_matches?(
        %Transition{condition: {:output_matches, pattern}},
        %Result{output: output}
      ) do
    regex = if is_binary(pattern), do: Regex.compile!(pattern), else: pattern
    Regex.match?(regex, output)
  end

  def transition_matches?(
        %Transition{condition: {:exit_code, code}},
        %Result{exit_code: exit_code}
      )
      when not is_nil(exit_code) do
    exit_code == code
  end

  def transition_matches?(
        %Transition{condition: func},
        %Result{output: output, exit_code: exit_code}
      )
      when is_function(func, 2) do
    safe_call_function(func, output, exit_code)
  end

  def transition_matches?(%Transition{}, %Result{}), do: false

  defp safe_call_function(func, output, exit_code) do
    try do
      func.(output, exit_code || 0)
    rescue
      _ -> false
    end
  end

  @doc """
  Build a transition map for a workflow.

  Returns a map of stage_id => list of possible next stages.
  """
  @spec build_transition_map([Stage.t()]) :: %{Stage.stage_id() => [Stage.stage_id()]}
  def build_transition_map(stages) do
    stages
    |> Enum.map(fn stage ->
      next_stages = get_all_possible_transitions(stage)
      {stage.id, next_stages}
    end)
    |> Map.new()
  end

  @doc """
  Get all possible next stages from a stage.

  Combines explicit transitions and shortcuts.
  """
  @spec get_all_possible_transitions(Stage.t()) :: [Stage.stage_id()]
  def get_all_possible_transitions(%Stage{} = stage) do
    explicit =
      stage.transitions
      |> Enum.map(& &1.to_stage)

    shortcuts =
      [stage.on_success, stage.on_failure, stage.on_timeout]
      |> Enum.filter(&(&1 != nil))

    (explicit ++ shortcuts)
    |> Enum.uniq()
  end

  @doc """
  Validate that all transitions point to valid stages.
  """
  @spec validate_transitions(Stage.t(), MapSet.t(Stage.stage_id())) ::
          :ok | {:error, [{Stage.stage_id(), Stage.stage_id()}]}
  def validate_transitions(%Stage{} = stage, valid_stage_ids) do
    invalid =
      get_all_possible_transitions(stage)
      |> Enum.filter(fn target -> not MapSet.member?(valid_stage_ids, target) end)
      |> Enum.map(fn target -> {stage.id, target} end)

    if Enum.empty?(invalid) do
      :ok
    else
      {:error, invalid}
    end
  end
end
