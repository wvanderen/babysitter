defmodule Babysitter.StageContext do
  @moduledoc """
  Context that flows between stages in a workflow execution.

  Tracks:
  - variables: Key-value pairs extracted from stage outputs
  - error_context: Accumulated errors and failures
  - handoff_data: Context from TD handoffs
  - stage_history: Results from previous stages

  ## Usage

      # Create initial context
      context = StageContext.new(issue_id: "td-123")
      
      # Merge handoff data
      context = StageContext.merge_handoff(context, issue_id)
      
      # Execute stage with context
      {:ok, result} = StageExecutor.execute(stage, session_id, context: context)
      
      # Update context from result
      context = StageContext.record_stage_result(context, result)
      
      # Extract variables from output
      context = StageContext.extract_from_output(context, "branch", ~r/branch:\\s*(\\S+)/)
      
      # Use variables in next stage
      branch = StageContext.get_variable(context, "branch")
  """

  alias Babysitter.{Context, StageExecutor.Result}

  @type variable_key :: atom() | String.t()
  @type variable_value :: term()

  @type stage_result :: %{
          stage_id: term(),
          status: atom(),
          output: String.t(),
          exit_code: non_neg_integer() | nil,
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          error: String.t() | nil
        }

  @type error_entry :: %{
          stage_id: term(),
          message: String.t(),
          timestamp: DateTime.t(),
          type: :validation | :execution | :timeout
        }

  @type t :: %__MODULE__{
          issue_id: String.t() | nil,
          workflow_id: String.t() | nil,
          session_id: String.t() | nil,
          variables: %{variable_key() => variable_value()},
          error_context: [error_entry()],
          handoff_data: Context.context() | nil,
          stage_history: [stage_result()],
          started_at: DateTime.t() | nil,
          metadata: map()
        }

  @enforce_keys []
  defstruct [
    :issue_id,
    :workflow_id,
    :session_id,
    variables: %{},
    error_context: [],
    handoff_data: nil,
    stage_history: [],
    started_at: nil,
    metadata: %{}
  ]

  @doc """
  Create a new stage context.

  ## Options
    * `:issue_id` - TD issue identifier
    * `:workflow_id` - Workflow identifier
    * `:session_id` - Session identifier
    * `:variables` - Initial variables map
    * `:metadata` - Additional metadata

  ## Examples

      iex> StageContext.new(issue_id: "td-123")
      %StageContext{issue_id: "td-123", ...}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      issue_id: Keyword.get(opts, :issue_id),
      workflow_id: Keyword.get(opts, :workflow_id),
      session_id: Keyword.get(opts, :session_id),
      variables: Keyword.get(opts, :variables, %{}),
      metadata: Keyword.get(opts, :metadata, %{}),
      started_at: DateTime.utc_now()
    }
  end

  @doc """
  Create context and merge handoff data in one step.

  ## Examples

      iex> StageContext.from_issue("td-123")
      %StageContext{issue_id: "td-123", handoff_data: %{...}}
  """
  @spec from_issue(String.t(), keyword()) :: t()
  def from_issue(issue_id, opts \\ []) do
    opts = Keyword.put(opts, :issue_id, issue_id)
    context = new(opts)
    merge_handoff(context, issue_id)
  end

  @doc """
  Merge handoff context from TD issue.

  ## Examples

      iex> context = StageContext.new(issue_id: "td-123")
      iex> StageContext.merge_handoff(context, "td-123")
      %StageContext{handoff_data: %{done: [...], remaining: [...], ...}}
  """
  @spec merge_handoff(t(), String.t()) :: t()
  def merge_handoff(%__MODULE__{} = context, issue_id) do
    handoff_data = Context.from_handoff(issue_id)
    %{context | issue_id: issue_id, handoff_data: handoff_data}
  end

  @doc """
  Set a variable in the context.

  ## Examples

      iex> context = StageContext.new()
      iex> StageContext.put_variable(context, :branch, "main")
      %StageContext{variables: %{branch: "main"}}
  """
  @spec put_variable(t(), variable_key(), variable_value()) :: t()
  def put_variable(%__MODULE__{variables: vars} = context, key, value) do
    %{context | variables: Map.put(vars, normalize_key(key), value)}
  end

  @doc """
  Put multiple variables at once.

  ## Examples

      iex> context = StageContext.new()
      iex> StageContext.put_variables(context, %{branch: "main", commit: "abc123"})
  """
  @spec put_variables(t(), map()) :: t()
  def put_variables(%__MODULE__{variables: vars} = context, new_vars) when is_map(new_vars) do
    normalized = Map.new(new_vars, fn {k, v} -> {normalize_key(k), v} end)
    %{context | variables: Map.merge(vars, normalized)}
  end

  @doc """
  Get a variable from the context.

  ## Examples

      iex> context = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.get_variable(context, :branch)
      "main"
      iex> StageContext.get_variable(context, :missing, "default")
      "default"
  """
  @spec get_variable(t(), variable_key(), variable_value()) :: variable_value()
  def get_variable(%__MODULE__{variables: vars}, key, default \\ nil) do
    Map.get(vars, normalize_key(key), default)
  end

  @doc """
  Get all variables as a map.

  ## Examples

      iex> context = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.get_all_variables(context)
      %{branch: "main"}
  """
  @spec get_all_variables(t()) :: map()
  def get_all_variables(%__MODULE__{variables: vars}), do: vars

  @doc """
  Delete a variable from the context.

  ## Examples

      iex> context = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.delete_variable(context, :branch)
      %StageContext{variables: %{}}
  """
  @spec delete_variable(t(), variable_key()) :: t()
  def delete_variable(%__MODULE__{variables: vars} = context, key) do
    %{context | variables: Map.delete(vars, normalize_key(key))}
  end

  @doc """
  Extract a variable from stage output using a pattern.

  Supports:
  - Regex patterns (captures first group)
  - String patterns (exact match)
  - Function extractors

  ## Examples

      iex> context = StageContext.new()
      iex> output = "Current branch: main"
      iex> StageContext.extract_from_output(context, :branch, ~r/branch:\\s*(\\S+)/, output)
      %StageContext{variables: %{branch: "main"}}

      iex> output = "Build completed successfully"
      iex> StageContext.extract_from_output(context, :status, "successfully", output)
      %StageContext{variables: %{status: "successfully"}}
  """
  @spec extract_from_output(t(), variable_key(), Regex.t() | String.t() | function(), String.t()) ::
          t()
  def extract_from_output(%__MODULE__{} = context, key, pattern, output) when is_binary(output) do
    case extract_value(pattern, output) do
      {:ok, value} -> put_variable(context, key, value)
      :not_found -> context
    end
  end

  def extract_from_output(%__MODULE__{} = context, _key, _pattern, _output), do: context

  defp extract_value(%Regex{} = regex, output) do
    case Regex.run(regex, output) do
      [_full | [capture | _]] -> {:ok, capture}
      [full] -> {:ok, full}
      nil -> :not_found
    end
  end

  defp extract_value(pattern, output) when is_binary(pattern) do
    if String.contains?(output, pattern) do
      {:ok, pattern}
    else
      :not_found
    end
  end

  defp extract_value(extractor, output) when is_function(extractor, 1) do
    case extractor.(output) do
      {:ok, value} -> {:ok, value}
      {:error, _} -> :not_found
      nil -> :not_found
      value -> {:ok, value}
    end
  end

  defp extract_value(_, _), do: :not_found

  @doc """
  Extract multiple variables using a map of patterns.

  ## Examples

      iex> context = StageContext.new()
      iex> output = "Branch: main, Commit: abc123"
      iex> patterns = %{branch: ~r/Branch:\\s*(\\S+)/, commit: ~r/Commit:\\s*(\\S+)/}
      iex> StageContext.extract_multiple(context, patterns, output)
      %StageContext{variables: %{branch: "main", commit: "abc123"}}
  """
  @spec extract_multiple(t(), map(), String.t()) :: t()
  def extract_multiple(%__MODULE__{} = context, patterns, output) when is_map(patterns) do
    Enum.reduce(patterns, context, fn {key, pattern}, ctx ->
      extract_from_output(ctx, key, pattern, output)
    end)
  end

  @doc """
  Record a stage execution result in the history.

  ## Examples

      iex> context = StageContext.new()
      iex> result = %Babysitter.StageExecutor.Result{stage_id: :analyze, status: :success, ...}
      iex> StageContext.record_stage_result(context, result)
  """
  @spec record_stage_result(t(), Result.t()) :: t()
  def record_stage_result(%__MODULE__{stage_history: history} = context, %Result{} = result) do
    entry = %{
      stage_id: result.stage_id,
      status: result.status,
      output: result.output,
      exit_code: result.exit_code,
      started_at: result.started_at,
      finished_at: result.finished_at,
      error: result.error
    }

    %{context | stage_history: history ++ [entry]}
  end

  @doc """
  Record an error in the error context.

  ## Examples

      iex> context = StageContext.new()
      iex> StageContext.record_error(context, :analyze, "Build failed", :execution)
  """
  @spec record_error(t(), term(), String.t(), atom()) :: t()
  def record_error(
        %__MODULE__{error_context: errors} = context,
        stage_id,
        message,
        type \\ :execution
      ) do
    entry = %{
      stage_id: stage_id,
      message: message,
      timestamp: DateTime.utc_now(),
      type: type
    }

    %{context | error_context: errors ++ [entry]}
  end

  @doc """
  Check if context has any errors.

  ## Examples

      iex> context = StageContext.record_error(StageContext.new(), :build, "Failed", :execution)
      iex> StageContext.has_errors?(context)
      true
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?(%__MODULE__{error_context: []}), do: false
  def has_errors?(%__MODULE__{error_context: [_ | _]}), do: true

  @doc """
  Get errors for a specific stage.

  ## Examples

      iex> context = StageContext.record_error(StageContext.new(), :build, "Failed", :execution)
      iex> StageContext.get_errors(context, :build)
      [%{stage_id: :build, message: "Failed", ...}]
  """
  @spec get_errors(t(), term()) :: [error_entry()]
  def get_errors(%__MODULE__{error_context: errors}, stage_id) do
    Enum.filter(errors, fn e -> e.stage_id == stage_id end)
  end

  @doc """
  Get all errors.

  ## Examples

      iex> StageContext.get_all_errors(context)
      [%{stage_id: :build, message: "Failed", ...}]
  """
  @spec get_all_errors(t()) :: [error_entry()]
  def get_all_errors(%__MODULE__{error_context: errors}), do: errors

  @doc """
  Clear all errors from context.

  ## Examples

      iex> context = StageContext.record_error(StageContext.new(), :build, "Failed", :execution)
      iex> StageContext.clear_errors(context)
      %StageContext{error_context: []}
  """
  @spec clear_errors(t()) :: t()
  def clear_errors(%__MODULE__{} = context), do: %{context | error_context: []}

  @doc """
  Get the last stage result from history.

  ## Examples

      iex> StageContext.get_last_result(context)
      %{stage_id: :analyze, status: :success, ...}
  """
  @spec get_last_result(t()) :: stage_result() | nil
  def get_last_result(%__MODULE__{stage_history: []}), do: nil
  def get_last_result(%__MODULE__{stage_history: history}), do: List.last(history)

  @doc """
  Get result for a specific stage.

  ## Examples

      iex> StageContext.get_result(context, :analyze)
      %{stage_id: :analyze, status: :success, ...}
  """
  @spec get_result(t(), term()) :: stage_result() | nil
  def get_result(%__MODULE__{stage_history: history}, stage_id) do
    Enum.find(history, fn r -> r.stage_id == stage_id end)
  end

  @doc """
  Get the output from a specific stage.

  ## Examples

      iex> StageContext.get_stage_output(context, :analyze)
      "Analysis output..."
  """
  @spec get_stage_output(t(), term()) :: String.t() | nil
  def get_stage_output(%__MODULE__{} = context, stage_id) do
    case get_result(context, stage_id) do
      nil -> nil
      result -> result.output
    end
  end

  @doc """
  Convert context to a map suitable for template interpolation.

  This provides all context data in a format that can be used
  with the TemplateInterpolator module.

  ## Examples

      iex> context = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.to_template_context(context)
      %{variables: %{branch: "main"}, handoff: %{...}, errors: [], ...}
  """
  @spec to_template_context(t()) :: map()
  def to_template_context(%__MODULE__{} = context) do
    %{
      variables: context.variables,
      handoff: context.handoff_data || Context.empty_context(context.issue_id),
      errors: context.error_context,
      stage_history: context.stage_history,
      last_stage: get_last_result(context),
      issue_id: context.issue_id,
      workflow_id: context.workflow_id,
      session_id: context.session_id,
      has_errors: has_errors?(context)
    }
  end

  @doc """
  Build execution options for StageExecutor including context.

  This creates the options map expected by StageExecutor.execute/3
  that includes context variables as environment variables.

  ## Examples

      iex> context = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.to_execution_opts(context, max_wait: 60_000)
      [context: %StageContext{...}, env: [{"BRANCH", "main"}], max_wait: 60_000]
  """
  @spec to_execution_opts(t(), keyword()) :: keyword()
  def to_execution_opts(%__MODULE__{} = context, opts \\ []) do
    env_vars =
      context.variables
      |> Enum.map(fn {key, value} ->
        env_key = key |> to_string() |> String.upcase() |> String.replace(" ", "_")
        {env_key, to_string(value)}
      end)

    opts
    |> Keyword.put(:context, context)
    |> Keyword.update(:env, env_vars, fn existing ->
      existing ++ env_vars
    end)
  end

  @doc """
  Merge two contexts.

  The second context's variables and errors take precedence.
  Stage history is concatenated.

  ## Examples

      iex> c1 = StageContext.put_variable(StageContext.new(), :a, 1)
      iex> c2 = StageContext.put_variable(StageContext.new(), :b, 2)
      iex> StageContext.merge(c1, c2)
      %StageContext{variables: %{a: 1, b: 2}}
  """
  @spec merge(t(), t()) :: t()
  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      issue_id: right.issue_id || left.issue_id,
      workflow_id: right.workflow_id || left.workflow_id,
      session_id: right.session_id || left.session_id,
      variables: Map.merge(left.variables, right.variables),
      error_context: left.error_context ++ right.error_context,
      handoff_data: right.handoff_data || left.handoff_data,
      stage_history: left.stage_history ++ right.stage_history,
      started_at: left.started_at,
      metadata: Map.merge(left.metadata, right.metadata)
    }
  end

  @doc """
  Create a child context inheriting from parent.

  Useful for sub-workflows or retry attempts.

  ## Examples

      iex> parent = StageContext.put_variable(StageContext.new(), :branch, "main")
      iex> StageContext.child(parent, retry: 1)
      %StageContext{variables: %{branch: "main"}, metadata: %{retry: 1}}
  """
  @spec child(t(), keyword()) :: t()
  def child(%__MODULE__{} = parent, opts \\ []) do
    %__MODULE__{
      issue_id: Keyword.get(opts, :issue_id, parent.issue_id),
      workflow_id: Keyword.get(opts, :workflow_id, parent.workflow_id),
      session_id: Keyword.get(opts, :session_id, parent.session_id),
      variables: Map.merge(parent.variables, Keyword.get(opts, :variables, %{})),
      error_context: parent.error_context,
      handoff_data: parent.handoff_data,
      stage_history: [],
      started_at: DateTime.utc_now(),
      metadata: Map.merge(parent.metadata, Keyword.get(opts, :metadata, %{}))
    }
  end

  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key(key) when is_atom(key), do: key
end
