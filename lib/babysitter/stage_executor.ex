defmodule Babysitter.StageExecutor do
  @moduledoc """
  Executes stages within a session's tmux environment.

  Handles building commands, running in tmux, capturing output,
  and determining execution results.
  """

  alias Babysitter.{Session, Stage, Tmux, Validation, TemplateInterpolator}

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
            error: String.t() | nil,
            validation_errors: [String.t()] | nil
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
      error: nil,
      validation_errors: nil
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
  def execute(stage, session_id, opts \\ [])

  def execute(%Stage{type: :action} = stage, session_id, opts) do
    execute_action(stage, session_id, opts)
  end

  def execute(%Stage{type: :decision} = stage, session_id, opts) do
    execute_decision(stage, session_id, opts)
  end

  def execute(%Stage{type: :validation} = stage, session_id, opts) do
    execute_validation(stage, session_id, opts)
  end

  def execute(%Stage{type: :interrupt} = stage, session_id, opts) do
    execute_interrupt(stage, session_id, opts)
  end

  def execute(%Stage{} = stage, session_id, opts) do
    execute_agent(stage, session_id, opts)
  end

  defp interpolate_with_context(text, opts) when is_binary(text) do
    context = Keyword.get(opts, :context, %{})
    variables = Keyword.get(opts, :variables, %{})
    full_context = deep_merge_context(variables, context)
    TemplateInterpolator.interpolate(text, full_context)
  end

  defp interpolate_with_context(text, _opts), do: text

  defp deep_merge_context(vars, ctx) when is_map(vars) and is_map(ctx) do
    Map.merge(vars, ctx, fn _k, v1, v2 ->
      if is_map(v1) and is_map(v2), do: Map.merge(v1, v2), else: v2
    end)
  end

  defp deep_merge_context(vars, _ctx), do: vars

  @doc """
  Execute an action stage (shell command) within a session.

  Action stages run shell commands and capture their exit codes.
  The command is executed in the session's tmux pane.

  ## Options
    * `:poll_interval` - Milliseconds between output polls (default: 500)
    * `:max_wait` - Maximum milliseconds to wait for completion (default: 300_000)
    * `:env` - Environment variables as keyword list or map

  ## Returns
    * `{:ok, Result.t()}` - Execution completed with exit code
    * `{:error, reason}` - Execution failed to start
  """
  @spec execute_action(Stage.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute_action(stage, session_id, opts \\ [])

  def execute_action(%Stage{type: :action} = stage, session_id, opts) do
    require Logger
    started_at = DateTime.utc_now()
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    max_wait = Keyword.get(opts, :max_wait, @default_max_wait)
    env = Keyword.get(opts, :env, [])

    with {:ok, session} <- get_session(session_id),
         {:ok, command, marker_id} <- build_action_command(stage, env, opts) do
      Logger.debug("Executing action #{stage.id}: #{command}")
      :ok = Tmux.send_keys(session.tmux_name, command)

      case wait_for_command_completion(
             session.tmux_name,
             started_at,
             poll_interval,
             max_wait,
             marker_id
           ) do
        {:ok, {output, exit_code}} ->
          Logger.debug("Action #{stage.id} completed with exit_code=#{exit_code}")
          finished_at = DateTime.utc_now()
          Session.append_output(session_id, output)

          status = if exit_code == 0, do: :success, else: :failure

          result = %Result{
            stage_id: stage.id,
            session_id: session_id,
            started_at: started_at,
            finished_at: finished_at,
            status: status,
            output: output,
            exit_code: exit_code
          }

          result = run_validations(result, stage, session_id)
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
             error: "Action timed out after #{max_wait}ms"
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

  def execute_action(%Stage{type: type}, _session_id, _opts) do
    {:error, {:invalid_stage_type, expected: :action, got: type}}
  end

  @doc """
  Execute a decision stage.

  Decision stages are simple pass-through stages that always succeed.
  They're used for branching logic in workflows.
  """
  @spec execute_decision(Stage.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute_decision(%Stage{type: :decision} = stage, session_id, _opts) do
    started_at = DateTime.utc_now()
    finished_at = DateTime.utc_now()

    result = %Result{
      stage_id: stage.id,
      session_id: session_id,
      started_at: started_at,
      finished_at: finished_at,
      status: :success,
      output: "",
      exit_code: 0
    }

    {:ok, result}
  end

  def execute_decision(%Stage{type: type}, _session_id, _opts) do
    {:error, {:invalid_stage_type, expected: :decision, got: type}}
  end

  @doc """
  Execute an interrupt stage.

  Interrupt stages pause the workflow and wait for human decision via TUI.
  The session transitions to `:awaiting_intervention` state and the
  TUI presents options (approve/deny/modify).

  This function triggers the interrupt and returns immediately with
  status indicating the interrupt is pending. The workflow should check
  for the interrupt decision using `Session.get_interrupt_state/1` or
  `Session.interrupt_pending?/1`.
  """
  @spec execute_interrupt(Stage.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def execute_interrupt(%Stage{type: :interrupt} = stage, session_id, _opts) do
    started_at = DateTime.utc_now()
    finished_at = DateTime.utc_now()

    prompt = interpolate_with_context(stage.interrupt_prompt || "Approval required", [])
    options = stage.interrupt_options || ["approve", "deny", "modify"]

    case Session.interrupt(session_id, prompt, options, stage.id) do
      {:ok, _status} ->
        result = %Result{
          stage_id: stage.id,
          session_id: session_id,
          started_at: started_at,
          finished_at: finished_at,
          status: :success,
          output: "Waiting for human decision: #{prompt}",
          exit_code: 0
        }

        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def execute_interrupt(%Stage{type: type}, _session_id, _opts) do
    {:error, {:invalid_stage_type, expected: :interrupt, got: type}}
  end

  @doc """
  Execute a validation stage.

  Validation stages run validations against the session's accumulated output
  without executing any command or prompt. Useful for checkpoint validations.
  """
  @spec execute_validation(Stage.t(), String.t(), keyword()) ::
          {:ok, Result.t()} | {:error, term()}
  def execute_validation(%Stage{type: :validation} = stage, session_id, _opts) do
    started_at = DateTime.utc_now()

    with {:ok, session} <- get_session(session_id) do
      output = session.output_buffer || ""
      finished_at = DateTime.utc_now()

      result = %Result{
        stage_id: stage.id,
        session_id: session_id,
        started_at: started_at,
        finished_at: finished_at,
        status: :success,
        output: output,
        exit_code: 0
      }

      result = run_validations(result, stage, session_id)
      {:ok, result}
    end
  end

  def execute_validation(%Stage{type: type}, _session_id, _opts) do
    {:error, {:invalid_stage_type, expected: :validation, got: type}}
  end

  @doc """
  Execute an agent stage within a session.

  Agent stages send prompts to an AI agent running in the tmux session.
  """
  @spec execute_agent(Stage.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def execute_agent(%Stage{} = stage, session_id, opts \\ []) do
    started_at = DateTime.utc_now()

    with {:ok, session} <- get_session(session_id),
         :ok <- validate_stage_type(stage, :agent),
         :ok <- Session.ensure_agent_started(session_id),
         {:ok, command} <- build_command(stage, opts) do
      agent = stage.agent || session.agent
      opts_with_agent = Keyword.put(opts, :agent, agent)

      case run_in_tmux(session.tmux_name, command, opts_with_agent) do
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

          result = run_validations(result, stage, session_id)
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
         :ok <- Session.ensure_agent_started(session_id),
         {:ok, command} <- build_command(stage, opts) do
      agent = stage.agent || session.agent
      :ok = send_agent_prompt(session.tmux_name, command, agent)

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

          result = run_validations(result, stage, session_id)
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

  @doc """
  Run stage validations and update result if any fail.

  Returns the result with status set to :failure if validations fail.
  Also stores validation result in the session.
  """
  @spec run_validations(Result.t(), Stage.t(), String.t()) :: Result.t()
  def run_validations(%Result{} = result, %Stage{validations: []}, _session_id), do: result

  def run_validations(%Result{} = result, %Stage{validations: validations}, session_id) do
    Process.sleep(500)

    case validate_result(result, validations) do
      :ok ->
        result

      {:error, errors} ->
        require Logger
        Logger.warning("Stage #{result.stage_id} validation failed: #{inspect(errors)}")

        validation_result = %Babysitter.Validation.Result{
          type: :custom,
          status: :fail,
          output: result.output,
          exit_code: result.exit_code,
          error: Enum.join(errors, "; "),
          started_at: result.started_at,
          finished_at: result.finished_at
        }

        Session.store_validation_result(session_id, result.stage_id, validation_result)

        %{result | status: :failure, validation_errors: errors}
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

  defp build_command(%Stage{prompt: prompt}, opts) when is_binary(prompt) and prompt != "" do
    {:ok, interpolate_with_context(prompt, opts)}
  end

  defp build_command(%Stage{prompt: nil}, _opts) do
    {:error, :no_prompt_defined}
  end

  defp build_command(%Stage{prompt: ""}, _opts) do
    {:error, :empty_prompt}
  end

  defp build_action_command(%Stage{command: command}, env, opts)
       when is_binary(command) and command != "" do
    interpolated = interpolate_with_context(command, opts)
    env_prefix = build_env_prefix(env)
    marker_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    wrapped_command =
      "#{env_prefix}(#{interpolated}); RET=$?; echo \"BABYSITTER_EXIT_${RET}_CODE_#{marker_id}\""

    {:ok, wrapped_command, marker_id}
  end

  defp build_action_command(%Stage{command: nil}, _env, _opts) do
    {:error, :no_command_defined}
  end

  defp build_action_command(%Stage{command: ""}, _env, _opts) do
    {:error, :empty_command}
  end

  defp build_env_prefix([]), do: ""

  defp build_env_prefix(env) when is_list(env) do
    exports =
      env
      |> Enum.map(fn {key, value} -> "export #{key}=#{escape_shell_value(value)}" end)
      |> Enum.join("; ")

    "#{exports}; "
  end

  defp build_env_prefix(env) when is_map(env) do
    exports =
      env
      |> Enum.map(fn {key, value} -> "export #{key}=#{escape_shell_value(value)}" end)
      |> Enum.join("; ")

    "#{exports}; "
  end

  defp escape_shell_value(value) when is_binary(value) do
    if String.contains?(value, [" ", "'", "\"", "$", "\\"]) do
      "'#{String.replace(value, "'", "'\\''")}'"
    else
      value
    end
  end

  defp escape_shell_value(value), do: to_string(value)

  defp wait_for_command_completion(tmux_name, started_at, poll_interval, max_wait, marker_id) do
    deadline = DateTime.add(started_at, max_wait, :millisecond)
    do_wait_for_command(tmux_name, deadline, poll_interval, marker_id, nil)
  end

  defp do_wait_for_command(tmux_name, deadline, poll_interval, marker_id, _last_output) do
    if DateTime.compare(DateTime.utc_now(), deadline) == :gt do
      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) -> {:timeout, output}
        _ -> {:timeout, ""}
      end
    else
      Process.sleep(poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          case extract_exit_code(output, marker_id) do
            {:ok, exit_code, clean_output} ->
              {:ok, {clean_output, exit_code}}

            :not_found ->
              do_wait_for_command(tmux_name, deadline, poll_interval, marker_id, output)
          end

        {:error, _} = error ->
          error
      end
    end
  end

  defp extract_exit_code(output, marker_id) do
    regex = ~r/BABYSITTER_EXIT_(\d+)_CODE_#{marker_id}\b/

    case Regex.run(regex, output) do
      [full_match, exit_code_str] ->
        exit_code = String.to_integer(exit_code_str)
        clean_output = String.replace(output, full_match, "")
        {:ok, exit_code, clean_output}

      _ ->
        :not_found
    end
  end

  defp run_in_tmux(tmux_name, command, opts) do
    max_wait = Keyword.get(opts, :max_wait, @default_max_wait)
    poll_interval = Keyword.get(opts, :poll_interval, @default_poll_interval)
    agent = Keyword.get(opts, :agent)

    send_agent_prompt(tmux_name, command, agent)

    started = System.monotonic_time(:millisecond)

    case poll_for_agent_completion(tmux_name, started, max_wait, poll_interval) do
      {:ok, output} -> {:ok, {output, 0}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_agent_prompt(tmux_name, command, :pi) do
    :ok = Tmux.send_keys(tmux_name, command, enter: false)
    Process.sleep(100)
    :ok = Tmux.send_keys(tmux_name, "Enter", enter: false)
  end

  defp send_agent_prompt(tmux_name, command, _agent) do
    :ok = Tmux.send_keys(tmux_name, command)
  end

  defp poll_for_agent_completion(tmux_name, started, max_wait, poll_interval) do
    stable_threshold = 5000
    do_poll_for_agent(tmux_name, started, max_wait, poll_interval, stable_threshold, nil, 0)
  end

  defp do_poll_for_agent(
         tmux_name,
         started,
         max_wait,
         poll_interval,
         stable_threshold,
         last_output,
         stable_ms
       ) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - started

    if elapsed > max_wait do
      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) -> {:ok, output}
        {:error, _} -> {:error, :timeout}
      end
    else
      Process.sleep(poll_interval)

      case Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          normalized = normalize_for_stability(output)
          last_normalized = if last_output, do: normalize_for_stability(last_output), else: nil

          new_stable_ms =
            if normalized == last_normalized do
              stable_ms + poll_interval
            else
              0
            end

          if new_stable_ms >= stable_threshold do
            {:ok, output}
          else
            do_poll_for_agent(
              tmux_name,
              started,
              max_wait,
              poll_interval,
              stable_threshold,
              output,
              new_stable_ms
            )
          end

        {:error, _} = error ->
          error
      end
    end
  end

  @doc false
  def normalize_for_stability(output) when is_binary(output) do
    output
    |> strip_ansi_codes()
    |> strip_box_drawing()
    |> String.trim()
  end

  @doc false
  def strip_ansi_codes(output) do
    Regex.replace(~r/\x1b\[[0-9;]*[a-zA-Z]/, output, "")
  end

  @doc false
  def strip_box_drawing(output) do
    output
    |> String.replace(~r/[─│┌┐└┘├┤┬┴┼╭╮╯╰╱╲╳]/, "")
    |> String.replace(~r/[▀▄█▓▒░]/, "")
    |> String.replace(~r/[►◄▲▼]/, "")
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
