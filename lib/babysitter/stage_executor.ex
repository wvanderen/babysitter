defmodule Babysitter.StageExecutor do
  @moduledoc """
  Executes stages within a session's tmux environment.

  Handles building commands, running in tmux, capturing output,
  and determining execution results.
  """

  alias Babysitter.{Session, Stage, Tmux, Validation}

  @type execution_status :: :success | :failure | :timeout
  @type exit_code :: non_neg_integer() | nil

  @type result :: %__MODULE__.Result{
          status: execution_status(),
          output: String.t(),
          exit_code: exit_code(),
          stage_id: Stage.stage_id(),
          session_id: String.t(),
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          error: String.t() | nil
        }

  defmodule Result do
    @moduledoc """
    Result of a stage execution.
    """
    @type t :: %__MODULE__{
            status: :success | :failure | :timeout,
            output: String.t(),
            exit_code: non_neg_integer() | nil,
            stage_id: Babysitter.Stage.stage_id(),
            session_id: String.t(),
            started_at: DateTime.t(),
            finished_at: DateTime.t(),
            error: String.t() | nil
          }

    @enforce_keys [:stage_id, :session_id, :started_at, :finished_at]
    defstruct [
      :stage_id,
      :session_id,
      :started_at,
      :finished_at,
      status: :failure,
      output: "",
      exit_code: nil,
      error: nil
    ]

    @spec success?(t()) :: boolean()
    def success?(%__MODULE__{status: :success}), do: true
    def success?(%__MODULE__{}), do: false

    @spec timeout?(t()) :: boolean()
    def timeout?(%__MODULE__{status: :timeout}), do: true
    def timeout?(%__MODULE__{}), do: false
  end

  @default_poll_interval 500
  @default_max_wait 300_000

  @doc """
  Execute a stage within a session.

  ## Options
    * `:poll_interval` - Milliseconds between output polls (default: 500)
    * `:max_wait` - Maximum milliseconds to wait for completion (default: 300_000)
    * `:completion_check` - Function to check if execution is complete

  ## Returns
    * `{:ok, Result.t()}` - Execution completed
    * `{:error, reason}` - Execution failed to start
  """
  @spec execute(Stage.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute(%Stage{} = stage, session_id, opts \\ []) do
    started_at = DateTime.utc_now()

    with {:ok, session} <- get_session(session_id),
         :ok <- validate_stage_type(stage, :agent),
         {:ok, command} <- build_command(stage) do
      case run_in_tmux(session.tmux_name, command, opts) do
        {:ok, {output, exit_code}} ->
          finished_at = DateTime.utc_now()

          result =
            build_result(
              stage,
              session_id,
              output,
              exit_code,
              started_at,
              finished_at
            )

          {:ok, result}

        {:error, reason} ->
          finished_at = DateTime.utc_now()

          {:ok,
           %Result{
             stage_id: stage.id,
             session_id: session_id,
             started_at: started_at,
             finished_at: finished_at,
             status: :failure,
             error: inspect(reason)
           }}
      end
    end
  end

  @doc """
  Execute a stage and wait for completion with output polling.

  This is useful for agent stages that may take time to complete.
  Polls the tmux pane for output until completion or timeout.
  """
  @spec execute_and_wait(Stage.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute_and_wait(%Stage{} = stage, session_id, opts \\ []) do
    started_at = DateTime.utc_now()
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    max_wait = Keyword.get(opts, :max_wait, @default_max_wait)
    completion_check = Keyword.get(opts, :completion_check)

    with {:ok, session} <- get_session(session_id),
         :ok <- validate_stage_type(stage, :agent),
         {:ok, command} <- build_command(stage) do
      :ok = Tmux.send_keys(session.tmux_name, command)

      case wait_for_completion(
             session.tmux_name,
             started_at,
             poll_interval,
             max_wait,
             completion_check
           ) do
        {:ok, output} ->
          finished_at = DateTime.utc_now()
          Session.append_output(session_id, output)

          result = %Result{
            stage_id: stage.id,
            session_id: session_id,
            started_at: started_at,
            finished_at: finished_at,
            status: :success,
            output: output,
            exit_code: 0
          }

          {:ok, result}

        {:timeout, output} ->
          finished_at = DateTime.utc_now()
          Session.append_output(session_id, output)

          {:ok,
           %Result{
             stage_id: stage.id,
             session_id: session_id,
             started_at: started_at,
             finished_at: finished_at,
             status: :timeout,
             output: output,
             exit_code: nil,
             error: "Execution timed out after #{max_wait}ms"
           }}

        {:error, reason} ->
          finished_at = DateTime.utc_now()

          {:ok,
           %Result{
             stage_id: stage.id,
             session_id: session_id,
             started_at: started_at,
             finished_at: finished_at,
             status: :failure,
             error: inspect(reason)
           }}
      end
    end
  end

  @doc """
  Run validations against an execution result.
  """
  @spec validate_result(Result.t(), [Validation.t()]) :: :ok | {:error, [String.t()]}
  def validate_result(%Result{} = result, validations) do
    results =
      validations
      |> Enum.map(fn validation ->
        Validation.run(validation, result.output, result.exit_code || 0)
      end)

    errors =
      results
      |> Enum.filter(fn
        {:error, _} -> true
        _ -> false
      end)
      |> Enum.map(fn {:error, msg} -> msg end)

    if Enum.empty?(errors) do
      :ok
    else
      {:error, errors}
    end
  end

  defp get_session(session_id) do
    case Session.whereis(session_id) do
      nil -> {:error, {:session_not_found, session_id}}
      _pid -> Session.get_state(session_id)
    end
  end

  defp validate_stage_type(%Stage{type: type}, expected) when type == expected, do: :ok

  defp validate_stage_type(%Stage{type: type}, expected) do
    {:error, {:invalid_stage_type, expected: expected, got: type}}
  end

  defp build_command(%Stage{prompt: prompt}) when is_binary(prompt) and prompt != "" do
    {:ok, prompt}
  end

  defp build_command(%Stage{prompt: nil}) do
    {:error, :no_prompt_defined}
  end

  defp build_command(%Stage{prompt: ""}) do
    {:error, :empty_prompt}
  end

  defp run_in_tmux(tmux_name, command, opts) do
    max_wait = Keyword.get(opts, :max_wait, @default_max_wait)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)

    :ok = Tmux.send_keys(tmux_name, command)

    started = System.monotonic_time(:millisecond)

    case poll_for_completion(tmux_name, started, max_wait, poll_interval) do
      {:ok, output} -> {:ok, {output, 0}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp poll_for_completion(tmux_name, started, max_wait, poll_interval) do
    now = System.monotonic_time(:millisecond)

    if now - started > max_wait do
      {:error, :timeout}
    else
      Process.sleep(poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          {:ok, output}

        {:error, _} = error ->
          error
      end
    end
  end

  defp wait_for_completion(tmux_name, started_at, poll_interval, max_wait, completion_check) do
    deadline = DateTime.add(started_at, max_wait, :millisecond)
    do_wait_for_completion(tmux_name, deadline, poll_interval, completion_check, "")
  end

  defp do_wait_for_completion(tmux_name, deadline, poll_interval, nil, last_output) do
    if DateTime.compare(DateTime.utc_now(), deadline) == :gt do
      {:timeout, last_output}
    else
      Process.sleep(poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          {:ok, output}

        {:error, _} = error ->
          error
      end
    end
  end

  defp do_wait_for_completion(tmux_name, deadline, poll_interval, check_fn, _last_output)
       when is_function(check_fn, 1) do
    if DateTime.compare(DateTime.utc_now(), deadline) == :gt do
      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) -> {:timeout, output}
        {:error, _} -> {:timeout, ""}
      end
    else
      Process.sleep(poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          if check_fn.(output) do
            {:ok, output}
          else
            do_wait_for_completion(tmux_name, deadline, poll_interval, check_fn, output)
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp build_result(stage, session_id, output, exit_code, started_at, finished_at) do
    status = if exit_code == 0, do: :success, else: :failure

    %Result{
      stage_id: stage.id,
      session_id: session_id,
      started_at: started_at,
      finished_at: finished_at,
      status: status,
      output: output,
      exit_code: exit_code
    }
  end
end
