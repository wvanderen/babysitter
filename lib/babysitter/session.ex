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
          :initializing | :running | :paused | :completed | :failed | :escalated | :stopped
  @type session_id :: String.t()
  @type transition_error :: {:error, {:invalid_transition, status(), status()}}

  @derive {Jason.Encoder,
           only: [
             :id,
             :status,
             :tmux_name,
             :started_at,
             :metadata,
             :failure_reason,
             :escalation_reason,
             :validation_results
           ]}
  @type t :: %__MODULE__{
          id: session_id(),
          status: status(),
          tmux_name: String.t() | nil,
          started_at: DateTime.t() | nil,
          output_buffer: String.t(),
          buffer_size: non_neg_integer(),
          max_buffer_size: non_neg_integer(),
          metadata: map(),
          validation_results: %{optional(term()) => [Babysitter.Validation.Result.t()]}
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
    validation_results: %{}
  ]

  @valid_transitions %{
    initializing: [:running, :stopped, :failed],
    running: [:paused, :completed, :failed, :escalated, :stopped],
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

  def store_validation_result(id, stage_id, result) do
    GenServer.cast(via_tuple(id), {:store_validation_result, stage_id, result})
  end

  def get_validation_results(id, stage_id \\ nil) do
    GenServer.call(via_tuple(id), {:get_validation_results, stage_id})
  end

  def clear_validation_results(id, stage_id \\ nil) do
    GenServer.call(via_tuple(id), {:clear_validation_results, stage_id})
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    tmux_name = Keyword.get(opts, :tmux_name, "babysitter-#{id}")
    max_buffer = Keyword.get(opts, :max_buffer_size, 100_000)
    metadata = Keyword.get(opts, :metadata, %{})

    case Babysitter.Tmux.create_session(tmux_name) do
      :ok ->
        state = %__MODULE__{
          id: id,
          tmux_name: tmux_name,
          status: :running,
          started_at: DateTime.utc_now(),
          max_buffer_size: max_buffer,
          metadata: metadata
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:tmux_error, reason}}
    end
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

  def handle_call(:pause, _from, state) do
    with :ok <- validate_transition(state.status, :paused) do
      Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
      {:reply, {:ok, :paused}, %{state | status: :paused}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:resume, _from, state) do
    with :ok <- validate_transition(state.status, :running) do
      Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
      {:reply, {:ok, :running}, %{state | status: :running}}
    else
      {:error, _} = error -> {:reply, error, state}
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

  @impl true
  def handle_cast({:append_output, output}, state) do
    new_buffer = append_to_buffer(state.output_buffer, output, state.max_buffer_size)
    new_size = byte_size(new_buffer)
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
