defmodule Babysitter.Session do
  @moduledoc """
  GenServer representing a single agent session.

  Each session has its own process holding:
  - Session state and metadata
  - Tmux session reference
  - Output buffer for capturing agent output

  State machine transitions:
  - :initializing → :running (on successful tmux creation)
  - :running → :paused (pause)
  - :paused → :running (resume)
  - :running → :completed (complete)
  - :running → :failed (fail)
  - :running → :escalated (escalate)
  - :paused → :escalated (escalate while paused)
  - :any → :stopped (stop)
  """

  use GenServer

  @type status ::
          :initializing
          | :running
          | :paused
          | :completed
          | :failed
          | :escalated
          | :stopped
          | :awaiting_intervention
  @type session_id :: String.t()
  @type stage_id :: String.t() | atom()
  @type transition_error :: {:error, {:invalid_transition, status(), status()}}
  @type interrupt_decision :: :approve | :deny | :modify

  @derive {Jason.Encoder,
           only: [
             :id,
             :status,
             :tmux_name,
             :started_at,
             :metadata,
             :failure_reason,
             :escalation_reason,
             :validation_results,
             :agent,
             :agent_started,
             :langgraph_thread_id,
             :langgraph_checkpoint_id,
             :interrupt_pending,
             :interrupt_prompt,
             :interrupt_options,
             :interrupt_stage_id,
             :interrupt_decision
           ]}
  @type t :: %{
          id: session_id(),
          status: status(),
          tmux_name: String.t() | nil,
          started_at: DateTime.t() | nil,
          output_buffer: String.t(),
          buffer_size: non_neg_integer(),
          max_buffer_size: non_neg_integer(),
          metadata: map(),
          validation_results: %{optional(term()) => [Babysitter.Validation.Result.t()]},
          agent: atom() | nil,
          agent_started: boolean(),
          langgraph_thread_id: String.t() | nil,
          langgraph_checkpoint_id: String.t() | nil,
          interrupt_pending: boolean(),
          interrupt_prompt: String.t() | nil,
          interrupt_options: [String.t()],
          interrupt_stage_id: String.t() | atom() | nil,
          interrupt_decision: :approve | :deny | :modify | nil
        }

  @enforce_keys [:id]
  defstruct [
    :id,
    :tmux_name,
    status: :initializing,
    started_at: nil,
    output_buffer: "",
    buffer_size: 0,
    max_buffer_size: 100_000,
    metadata: %{},
    failure_reason: nil,
    escalation_reason: nil,
    validation_results: %{},
    agent: nil,
    agent_started: false,
    langgraph_thread_id: nil,
    langgraph_checkpoint_id: nil,
    interrupt_pending: false,
    interrupt_prompt: nil,
    interrupt_options: [],
    interrupt_stage_id: nil,
    interrupt_decision: nil
  ]

  @valid_transitions %{
    initializing: [:running, :stopped, :failed],
    running: [:paused, :completed, :failed, :escalated, :stopped, :awaiting_intervention],
    awaiting_intervention: [:running, :stopped, :failed],
    paused: [:running, :escalated, :stopped],
    completed: [:stopped],
    failed: [:stopped],
    escalated: [:running, :stopped]
  }

  @spec valid_transition?(status(), status()) :: boolean()
  def valid_transition?(from_status, to_status) do
    to_status in Map.get(@valid_transitions, from_status, [])
  end

  @spec valid_transitions(status()) :: [status()]
  def valid_transitions(status) do
    Map.get(@valid_transitions, status, [])
  end

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    name = via_tuple(id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Start a session in recovery mode, attaching to an existing tmux session.

  Unlike start_link/1, this does not create a new tmux session.
  It attaches to an existing tmux session and restores state from persistence.

  ## Options

    * `:tmux_name` - Required. Name of the existing tmux session
    * `:status` - Status to restore (overrides persisted value)
    * `:started_at` - Original start time (overrides persisted value)
    * `:output_buffer` - Restored output buffer (overrides persisted value)
    * `:metadata` - Restored metadata (overrides persisted value)
    * `:failure_reason` - Restored failure reason (overrides persisted value)
    * `:escalation_reason` - Restored escalation reason (overrides persisted value)
    * `:validation_results` - Restored validation results (overrides persisted value)

  ## Examples

      {:ok, pid} = Session.start_recovery("session-123", tmux_name: "babysitter-session-123")
  """
  @spec start_recovery(session_id(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_recovery(id, opts) do
    tmux_name = Keyword.fetch!(opts, :tmux_name)

    if Babysitter.Tmux.session_exists?(tmux_name) do
      opts = Keyword.put(opts, :id, id)
      opts = Keyword.put(opts, :recovery_mode, true)

      opts =
        case Babysitter.State.Persistence.load_session(id) do
          {:ok, persisted} ->
            merge_persisted_state(opts, persisted)

          {:error, :not_found} ->
            opts
        end

      DynamicSupervisor.start_child(Babysitter.SessionSupervisor, {__MODULE__, opts})
    else
      {:error, {:tmux_not_found, tmux_name}}
    end
  end

  defp merge_persisted_state(opts, persisted) do
    defaults = [
      status: String.to_existing_atom(persisted.status),
      started_at: persisted.started_at,
      output_buffer: persisted.output_buffer,
      metadata: persisted.metadata,
      failure_reason: persisted.failure_reason,
      escalation_reason: persisted.escalation_reason,
      validation_results: persisted.validation_results
    ]

    Keyword.merge(defaults, opts)
  end

  def via_tuple(id) do
    {:via, Registry, {Babysitter.SessionRegistry, id}}
  end

  def whereis(id) do
    case Registry.lookup(Babysitter.SessionRegistry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def get_state(id) do
    GenServer.call(via_tuple(id), :get_state)
  end

  def get_status(id) do
    GenServer.call(via_tuple(id), :get_status)
  end

  def get_output(id) do
    GenServer.call(via_tuple(id), :get_output)
  end

  def append_output(id, output) do
    GenServer.cast(via_tuple(id), {:append_output, output})
  end

  def pause(id) do
    GenServer.call(via_tuple(id), :pause)
  end

  def resume(id) do
    GenServer.call(via_tuple(id), :resume)
  end

  @doc """
  Trigger an interrupt and pause the session for human decision.

  The session will transition to `:awaiting_intervention` state and
  store the interrupt details for the TUI to display.
  """
  @spec interrupt(session_id(), String.t(), [String.t()], stage_id()) ::
          {:ok, status()} | transition_error()
  def interrupt(id, prompt, options, stage_id) do
    GenServer.call(via_tuple(id), {:interrupt, prompt, options, stage_id})
  end

  @doc """
  Get the current interrupt state for a session.
  """
  @spec get_interrupt_state(session_id()) :: {:ok, map()} | {:error, :no_interrupt_pending}
  def get_interrupt_state(id) do
    GenServer.call(via_tuple(id), :get_interrupt_state)
  end

  @doc """
  Submit a human decision for a pending interrupt.

  The decision can be :approve, :deny, or :modify.
  """
  @spec submit_decision(session_id(), interrupt_decision(), String.t() | nil) ::
          {:ok, status()} | transition_error()
  def submit_decision(id, decision, modified_context \\ nil) do
    GenServer.call(via_tuple(id), {:submit_decision, decision, modified_context})
  end

  @doc """
  Check if session has a pending interrupt.
  """
  @spec interrupt_pending?(session_id()) :: boolean()
  def interrupt_pending?(id) do
    GenServer.call(via_tuple(id), :interrupt_pending?)
  end

  def stop(id) do
    GenServer.call(via_tuple(id), :stop)
  end

  def capture_tmux_output(id) do
    GenServer.call(via_tuple(id), :capture_tmux_output)
  end

  def clear_buffer(id) do
    GenServer.call(via_tuple(id), :clear_buffer)
  end

  def complete(id) do
    GenServer.call(via_tuple(id), :complete)
  end

  def fail(id, reason \\ nil) do
    GenServer.call(via_tuple(id), {:fail, reason})
  end

  def escalate(id, reason \\ nil) do
    GenServer.call(via_tuple(id), {:escalate, reason})
  end

  def valid_transitions_for(id) do
    GenServer.call(via_tuple(id), :valid_transitions)
  end

  def intervene(id, action, opts \\ []) do
    GenServer.call(via_tuple(id), {:intervene, action, opts})
  end

  def store_validation_result(id, stage_id, result) do
    GenServer.cast(via_tuple(id), {:store_validation_result, stage_id, result})
  end

  def get_validation_results(id, stage_id \\ nil) do
    GenServer.call(via_tuple(id), {:get_validation_results, stage_id})
  end

  def clear_validation_results(id, stage_id \\ nil) do
    GenServer.call(via_tuple(id), {:clear_validation_results, stage_id})
  end

  @spec set_langgraph_thread(session_id(), String.t()) :: :ok
  def set_langgraph_thread(id, thread_id) do
    GenServer.call(via_tuple(id), {:set_langgraph_thread, thread_id})
  end

  @spec update_langgraph_checkpoint(session_id(), String.t()) :: :ok | {:error, term()}
  def update_langgraph_checkpoint(id, checkpoint_id) do
    GenServer.call(via_tuple(id), {:update_langgraph_checkpoint, checkpoint_id})
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    recovery_mode = Keyword.get(opts, :recovery_mode, false)
    tmux_name = Keyword.get(opts, :tmux_name, "babysitter-#{id}")
    max_buffer = Keyword.get(opts, :max_buffer_size, 100_000)
    metadata = Keyword.get(opts, :metadata, %{})
    agent = Keyword.get(opts, :agent)

    if recovery_mode do
      init_recovery(id, tmux_name, max_buffer, opts)
    else
      init_new(id, tmux_name, max_buffer, metadata, agent)
    end
  end

  defp init_new(id, tmux_name, max_buffer, metadata, agent) do
    case Babysitter.Tmux.create_session(tmux_name) do
      :ok ->
        state = %__MODULE__{
          id: id,
          tmux_name: tmux_name,
          status: :running,
          started_at: DateTime.utc_now(),
          max_buffer_size: max_buffer,
          metadata: metadata,
          agent: agent,
          agent_started: false
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:tmux_error, reason}}
    end
  end

  defp init_recovery(id, tmux_name, max_buffer, opts) do
    status = Keyword.get(opts, :status, :running)
    started_at = Keyword.get(opts, :started_at)
    output_buffer = Keyword.get(opts, :output_buffer, "")
    metadata = Keyword.get(opts, :metadata, %{})
    failure_reason = Keyword.get(opts, :failure_reason)
    escalation_reason = Keyword.get(opts, :escalation_reason)
    validation_results = Keyword.get(opts, :validation_results, %{})

    validation_results = atomize_validation_keys(validation_results)

    {langgraph_thread_id, langgraph_checkpoint_id} =
      case Babysitter.State.Persistence.get_langgraph_session(id) do
        nil -> {nil, nil}
        mapping -> {mapping.thread_id, mapping.checkpoint_id}
      end

    state = %__MODULE__{
      id: id,
      tmux_name: tmux_name,
      status: status,
      started_at: started_at && convert_datetime(started_at),
      output_buffer: output_buffer,
      buffer_size: byte_size(output_buffer),
      max_buffer_size: max_buffer,
      metadata: metadata,
      failure_reason: failure_reason,
      escalation_reason: escalation_reason,
      validation_results: validation_results,
      agent: nil,
      agent_started: false,
      langgraph_thread_id: langgraph_thread_id,
      langgraph_checkpoint_id: langgraph_checkpoint_id
    }

    {:ok, state}
  end

  defp convert_datetime(%NaiveDateTime{} = dt), do: dt
  defp convert_datetime(datetime), do: datetime

  defp atomize_validation_keys(results) when is_map(results) do
    results
    |> Enum.map(fn {k, v} -> {maybe_atomize(k), v} end)
    |> Map.new()
  end

  defp atomize_validation_keys(results), do: results

  defp maybe_atomize(key) when is_atom(key), do: key
  defp maybe_atomize(key) when is_binary(key), do: String.to_existing_atom(key)
  defp maybe_atomize(key), do: key

  @doc """
  Ensure the agent is started in this session.
  Safe to call multiple times - only starts once.
  """
  @spec ensure_agent_started(session_id()) :: :ok | {:error, term()}
  def ensure_agent_started(id) do
    GenServer.call(via_tuple(id), :ensure_agent_started)
  end

  @doc """
  Check if the agent has been started.
  """
  @spec agent_started?(session_id()) :: boolean()
  def agent_started?(id) do
    GenServer.call(via_tuple(id), :agent_started?)
  end

  defp do_start_agent(_tmux_name, nil), do: :ok

  defp do_start_agent(tmux_name, agent_name) when is_atom(agent_name) do
    case Babysitter.Config.agent(agent_name) do
      nil ->
        {:error, {:unknown_agent, agent_name}}

      agent_config ->
        command = build_agent_command(agent_config)
        Process.sleep(200)
        Babysitter.Tmux.send_keys(tmux_name, command)
    end
  end

  defp do_start_agent(_tmux_name, agent_name) do
    {:error, {:invalid_agent_name, agent_name}}
  end

  defp build_agent_command(%{command: cmd, args: args}) when is_list(args) do
    Enum.join([cmd | args], " ")
  end

  defp build_agent_command(%{command: cmd}) do
    cmd
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end

  def handle_call(:get_output, _from, state) do
    {:reply, {:ok, state.output_buffer}, state}
  end

  def handle_call(:ensure_agent_started, _from, %__MODULE__{agent_started: true} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:ensure_agent_started, _from, %__MODULE__{agent: nil} = state) do
    {:reply, :ok, state}
  end

  def handle_call(:ensure_agent_started, _from, %__MODULE__{} = state) do
    case do_start_agent(state.tmux_name, state.agent) do
      :ok ->
        {:reply, :ok, %{state | agent_started: true}}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call(:agent_started?, _from, state) do
    {:reply, state.agent_started, state}
  end

  def handle_call(:pause, _from, state) do
    with :ok <- validate_transition(state.status, :paused) do
      Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
      Babysitter.Broadcast.session_status(state.id, state.status, :paused)
      {:reply, {:ok, :paused}, %{state | status: :paused}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:resume, _from, state) do
    with :ok <- validate_transition(state.status, :running) do
      Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
      Babysitter.Broadcast.session_status(state.id, state.status, :running)
      {:reply, {:ok, :running}, %{state | status: :running}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:interrupt, prompt, options, stage_id}, _from, state) do
    with :ok <- validate_transition(state.status, :awaiting_intervention) do
      new_state = %{
        state
        | status: :awaiting_intervention,
          interrupt_pending: true,
          interrupt_prompt: prompt,
          interrupt_options: options,
          interrupt_stage_id: stage_id,
          interrupt_decision: nil
      }

      {:reply, {:ok, :awaiting_intervention}, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:get_interrupt_state, _from, state) do
    if state.interrupt_pending do
      {:reply,
       {:ok,
        %{
          prompt: state.interrupt_prompt,
          options: state.interrupt_options,
          stage_id: state.interrupt_stage_id,
          session_id: state.id,
          output_buffer: state.output_buffer
        }}, state}
    else
      {:reply, {:error, :no_interrupt_pending}, state}
    end
  end

  def handle_call(:interrupt_pending?, _from, state) do
    {:reply, state.interrupt_pending, state}
  end

  def handle_call({:submit_decision, decision, _modified_context}, _from, state) do
    if state.interrupt_pending do
      with :ok <- validate_transition(state.status, :running) do
        new_state = %{
          state
          | status: :running,
            interrupt_pending: false,
            interrupt_decision: decision
        }

        {:reply, {:ok, :running}, new_state}
      else
        {:error, _} = error -> {:reply, error, state}
      end
    else
      {:reply, {:error, :no_interrupt_pending}, state}
    end
  end

  def handle_call(:complete, _from, state) do
    with :ok <- validate_transition(state.status, :completed) do
      {:reply, {:ok, :completed}, %{state | status: :completed}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:fail, reason}, _from, state) do
    with :ok <- validate_transition(state.status, :failed) do
      {:reply, {:ok, :failed}, %{state | status: :failed, failure_reason: reason}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:escalate, reason}, _from, state) do
    with :ok <- validate_transition(state.status, :escalated) do
      {:reply, {:ok, :escalated}, %{state | status: :escalated, escalation_reason: reason}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:intervene, action, opts}, _from, state) do
    reason = Keyword.get(opts, :reason)

    case action do
      :retry ->
        with :ok <- validate_transition(state.status, :running) do
          {:reply, {:ok, :retry}, %{state | status: :running, failure_reason: nil}}
        else
          {:error, _} = error -> {:reply, error, state}
        end

      :restart ->
        with :ok <- validate_transition(state.status, :running) do
          {:reply, {:ok, :restart}, %{state | status: :running, failure_reason: nil}}
        else
          {:error, _} = error -> {:reply, error, state}
        end

      :escalate ->
        with :ok <- validate_transition(state.status, :escalated) do
          {:reply, {:ok, :escalated}, %{state | status: :escalated, escalation_reason: reason}}
        else
          {:error, _} = error -> {:reply, error, state}
        end

      :skip ->
        {:reply, {:ok, :skip}, state}

      _ ->
        {:reply, {:error, {:unknown_action, action}}, state}
    end
  end

  def handle_call(:valid_transitions, _from, state) do
    {:reply, {:ok, valid_transitions(state.status)}, state}
  end

  def handle_call(:stop, _from, state) do
    if state.tmux_name do
      Babysitter.Tmux.kill_session(state.tmux_name)
    end

    {:reply, :ok, %{state | status: :stopped, tmux_name: nil}}
  end

  def handle_call(:capture_tmux_output, _from, state) do
    case Babysitter.Tmux.capture_pane(state.tmux_name) do
      output when is_binary(output) ->
        {:reply, {:ok, output}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear_buffer, _from, state) do
    {:reply, :ok, %{state | output_buffer: "", buffer_size: 0}}
  end

  def handle_call({:get_validation_results, nil}, _from, state) do
    {:reply, {:ok, state.validation_results}, state}
  end

  def handle_call({:get_validation_results, stage_id}, _from, state) do
    results = Map.get(state.validation_results, stage_id, [])
    {:reply, {:ok, results}, state}
  end

  def handle_call({:clear_validation_results, nil}, _from, state) do
    {:reply, :ok, %{state | validation_results: %{}}}
  end

  def handle_call({:clear_validation_results, stage_id}, _from, state) do
    new_results = Map.delete(state.validation_results, stage_id)
    {:reply, :ok, %{state | validation_results: new_results}}
  end

  def handle_call({:set_langgraph_thread, thread_id}, _from, state) do
    {:reply, :ok, %{state | langgraph_thread_id: thread_id}}
  end

  def handle_call({:update_langgraph_checkpoint, checkpoint_id}, _from, state) do
    case state.langgraph_thread_id do
      nil ->
        {:reply, {:error, :no_thread_set}, state}

      thread_id ->
        {:ok, _} =
          Babysitter.State.Persistence.save_langgraph_session(%{
            session_id: state.id,
            thread_id: thread_id,
            checkpoint_id: checkpoint_id
          })

        {:reply, :ok, %{state | langgraph_checkpoint_id: checkpoint_id}}
    end
  end

  @impl true
  def handle_cast({:append_output, output}, state) do
    new_buffer = append_to_buffer(state.output_buffer, output, state.max_buffer_size)
    new_size = byte_size(new_buffer)
    Babysitter.Broadcast.session_output(state.id, output)
    {:noreply, %{state | output_buffer: new_buffer, buffer_size: new_size}}
  end

  def handle_cast({:store_validation_result, stage_id, result}, state) do
    current_results = Map.get(state.validation_results, stage_id, [])
    updated_results = current_results ++ [result]
    new_validation_results = Map.put(state.validation_results, stage_id, updated_results)
    {:noreply, %{state | validation_results: new_validation_results}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.tmux_name && Babysitter.Tmux.session_exists?(state.tmux_name) do
      Babysitter.Tmux.kill_session(state.tmux_name)
    end

    :ok
  end

  defp append_to_buffer(buffer, new_data, max_size) do
    combined = buffer <> new_data

    if byte_size(combined) > max_size do
      drop_bytes = byte_size(combined) - max_size
      binary_part(combined, drop_bytes, max_size)
    else
      combined
    end
  end

  defp validate_transition(from_status, to_status) do
    if valid_transition?(from_status, to_status) do
      :ok
    else
      {:error, {:invalid_transition, from_status, to_status}}
    end
  end
end
