defmodule Babysitter.WorkflowInstance do
  @moduledoc """
  GenServer representing a single running workflow instance.

  Each instance tracks:
  - Current stage and execution state
  - Execution history
  - Variables for prompt interpolation
  - Crash recovery state

  State machine:
  - :pending -> :running (start)
  - :running -> :paused (pause)
  - :paused -> :running (resume)
  - :running -> :completed (complete)
  - :running -> :failed (fail)
  - :running -> :escalated (escalate)
  - any -> :stopped (stop)
  """

  use GenServer

  alias Babysitter.{Broadcast, StageExecutor, TransitionEngine, WorkflowStore}

  @type status :: :pending | :running | :paused | :completed | :failed | :escalated | :stopped
  @type instance_id :: String.t()

  @type t :: %__MODULE__{
          id: instance_id(),
          workflow_id: String.t(),
          status: status(),
          current_stage: atom() | nil,
          session_id: String.t() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          execution_history: [execution_entry()],
          variables: map(),
          failure_reason: String.t() | nil,
          escalation_reason: String.t() | nil,
          retry_count: non_neg_integer(),
          max_retries: non_neg_integer()
        }

  @type execution_entry :: %{
          stage_id: atom(),
          stage_type: atom() | nil,
          status: :success | :failure | :timeout,
          started_at: DateTime.t(),
          finished_at: DateTime.t(),
          output: String.t() | nil,
          error: String.t() | nil,
          duration_ms: non_neg_integer() | nil,
          metadata: map() | nil
        }

  @enforce_keys [:id, :workflow_id]
  defstruct [
    :id,
    :workflow_id,
    status: :pending,
    current_stage: nil,
    session_id: nil,
    started_at: nil,
    completed_at: nil,
    execution_history: [],
    variables: %{},
    failure_reason: nil,
    escalation_reason: nil,
    retry_count: 0,
    max_retries: 3
  ]

  def child_spec(opts) do
    id = Keyword.fetch!(opts, :id)

    %{
      id: {__MODULE__, id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      type: :worker
    }
  end

  @valid_transitions %{
    pending: [:running, :stopped],
    running: [:paused, :completed, :failed, :escalated, :stopped],
    paused: [:running, :escalated, :stopped],
    completed: [:stopped],
    failed: [:running, :stopped],
    escalated: [:running, :stopped]
  }

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def via_tuple(id) do
    {:via, Registry, {Babysitter.WorkflowRegistry, id}}
  end

  def whereis(id) do
    case Registry.lookup(Babysitter.WorkflowRegistry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def start(id, opts \\ []) do
    GenServer.call(via_tuple(id), {:start, opts})
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

  def get_state(id) do
    GenServer.call(via_tuple(id), :get_state)
  end

  def get_status(id) do
    GenServer.call(via_tuple(id), :get_status)
  end

  def get_history(id) do
    GenServer.call(via_tuple(id), :get_history)
  end

  def set_variable(id, key, value) do
    GenServer.cast(via_tuple(id), {:set_variable, key, value})
  end

  def set_variables(id, vars) when is_map(vars) do
    GenServer.cast(via_tuple(id), {:set_variables, vars})
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

  def retry(id) do
    GenServer.call(via_tuple(id), :retry)
  end

  def continue(id) do
    GenServer.cast(via_tuple(id), :continue)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    workflow_id = Keyword.fetch!(opts, :workflow_id)
    session_id = Keyword.get(opts, :session_id)
    variables = Keyword.get(opts, :variables, %{})
    max_retries = Keyword.get(opts, :max_retries, 3)

    state = %__MODULE__{
      id: id,
      workflow_id: workflow_id,
      session_id: session_id,
      variables: variables,
      max_retries: max_retries
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start, opts}, _from, state) do
    with :ok <- validate_transition(state.status, :running),
         {:ok, workflow} <- WorkflowStore.get(state.workflow_id),
         entry_point <- workflow.entry_point || List.first(workflow.stage_order) do
      session_id = Keyword.get(opts, :session_id, state.session_id)

      new_state = %{
        state
        | status: :running,
          current_stage: entry_point,
          session_id: session_id,
          started_at: DateTime.utc_now()
      }

      if session_id do
        send(self(), :execute_current_stage)
      end

      {:reply, {:ok, new_state}, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:pause, _from, state) do
    with :ok <- validate_transition(state.status, :paused) do
      {:reply, {:ok, :paused}, %{state | status: :paused}}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:resume, _from, state) do
    with :ok <- validate_transition(state.status, :running) do
      new_state = %{state | status: :running}
      send(self(), :execute_current_stage)
      {:reply, {:ok, :running}, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call(:stop, _from, state) do
    {:reply, :ok, %{state | status: :stopped, completed_at: DateTime.utc_now()}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end

  def handle_call(:get_history, _from, state) do
    {:reply, {:ok, state.execution_history}, state}
  end

  def handle_call(:complete, _from, state) do
    with :ok <- validate_transition(state.status, :completed) do
      {:reply, {:ok, :completed}, %{state | status: :completed, completed_at: DateTime.utc_now()}}
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

  def handle_call(:retry, _from, state) do
    with :ok <- validate_transition(state.status, :running),
         true <- state.retry_count < state.max_retries do
      new_state = %{
        state
        | status: :running,
          failure_reason: nil,
          retry_count: state.retry_count + 1
      }

      send(self(), :execute_current_stage)
      {:reply, {:ok, :retrying}, new_state}
    else
      false -> {:reply, {:error, :max_retries_exceeded}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_cast({:set_variable, key, value}, state) do
    {:noreply, %{state | variables: Map.put(state.variables, key, value)}}
  end

  def handle_cast({:set_variables, vars}, state) do
    {:noreply, %{state | variables: Map.merge(state.variables, vars)}}
  end

  def handle_cast(:continue, state) do
    if state.status == :running and state.current_stage != nil do
      send(self(), :execute_current_stage)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:execute_current_stage, state) do
    if state.status != :running do
      {:noreply, state}
    else
      case execute_stage(state) do
        {:ok, result, new_state} ->
          handle_stage_result(result, new_state)

        {:error, reason, new_state} ->
          {:noreply, %{new_state | status: :failed, failure_reason: inspect(reason)}}
      end
    end
  end

  def handle_info({:stage_timeout, stage_id}, state) do
    if state.current_stage == stage_id and state.status == :running do
      entry = %{
        stage_id: stage_id,
        stage_type: nil,
        status: :timeout,
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: nil,
        error: "Stage timed out",
        duration_ms: 0,
        metadata: nil
      }

      new_state = %{
        state
        | execution_history: state.execution_history ++ [entry],
          status: :failed,
          failure_reason: "Stage #{stage_id} timed out"
      }

      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.status == :running do
      Babysitter.State.Persistence.save_workflow_state(state)
    end

    :ok
  end

  defp execute_stage(%__MODULE__{current_stage: nil} = state) do
    {:error, :no_current_stage, state}
  end

  defp execute_stage(%__MODULE__{} = state) do
    with {:ok, workflow} <- WorkflowStore.get(state.workflow_id),
         stage when not is_nil(stage) <- Map.get(workflow.stages, state.current_stage),
         true <- state.session_id != nil do
      started_at = DateTime.utc_now()
      stage_id = state.current_stage

      Broadcast.stage_started(state.session_id, stage_id, %{
        type: stage.type,
        prompt: Map.get(stage, :prompt),
        command: Map.get(stage, :command)
      })

      case StageExecutor.execute(stage, state.session_id, build_executor_opts(state)) do
        {:ok, result} ->
          duration_ms = DateTime.diff(result.finished_at, started_at, :millisecond)

          Broadcast.stage_completed(state.session_id, stage_id, result.status, %{
            output: result.output,
            error: result.error,
            duration_ms: duration_ms
          })

          metadata = %{
            type: stage.type,
            command: Map.get(stage, :command),
            prompt: Map.get(stage, :prompt)
          }

          entry = %{
            stage_id: state.current_stage,
            stage_type: stage.type,
            status: result.status,
            started_at: started_at,
            finished_at: result.finished_at,
            output: result.output,
            error: result.error,
            duration_ms: duration_ms,
            metadata: metadata
          }

          new_state = %{state | execution_history: state.execution_history ++ [entry]}
          {:ok, result, new_state}

        {:error, reason} ->
          Broadcast.stage_completed(state.session_id, stage_id, :failure, %{
            error: inspect(reason),
            duration_ms: DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
          })

          {:error, reason, state}
      end
    else
      {:error, :not_found} -> {:error, :workflow_not_found, state}
      nil -> {:error, :stage_not_found, state}
      false -> {:error, :no_session, state}
    end
  end

  defp build_executor_opts(state) do
    opts = []

    if Map.has_key?(state.variables, :poll_interval) do
      Keyword.put(opts, :poll_interval, state.variables.poll_interval)
    else
      opts
    end
  end

  defp handle_stage_result(%StageExecutor.Result{status: :success} = result, state) do
    case TransitionEngine.next_stage(get_current_stage(state), result) do
      {:ok, :complete} ->
        broadcast_progress(state, :completed)
        {:noreply, %{state | status: :completed, completed_at: DateTime.utc_now()}}

      {:ok, next_stage_id} when is_atom(next_stage_id) ->
        Broadcast.stage_transition(
          state.session_id,
          state.current_stage,
          next_stage_id,
          "success"
        )

        new_state = %{state | current_stage: next_stage_id, retry_count: 0}
        broadcast_progress(new_state, :running)
        send(self(), :execute_current_stage)
        {:noreply, new_state}

      {:error, :no_transition_defined} ->
        broadcast_progress(state, :completed)
        {:noreply, %{state | status: :completed, completed_at: DateTime.utc_now()}}
    end
  end

  defp handle_stage_result(%StageExecutor.Result{status: :failure} = result, state) do
    case TransitionEngine.next_stage(get_current_stage(state), result) do
      {:ok, :complete} ->
        broadcast_progress(state, :completed)
        {:noreply, %{state | status: :completed, completed_at: DateTime.utc_now()}}

      {:ok, next_stage_id} when is_atom(next_stage_id) ->
        Broadcast.stage_transition(
          state.session_id,
          state.current_stage,
          next_stage_id,
          "failure"
        )

        new_state = %{state | current_stage: next_stage_id}
        broadcast_progress(new_state, :running)
        send(self(), :execute_current_stage)
        {:noreply, new_state}

      {:error, :no_transition_defined} ->
        if state.retry_count < state.max_retries do
          new_state = %{state | retry_count: state.retry_count + 1}
          send(self(), :execute_current_stage)
          {:noreply, new_state}
        else
          broadcast_progress(state, :failed)

          {:noreply,
           %{
             state
             | status: :failed,
               failure_reason: result.error || "Stage failed after #{state.max_retries} retries"
           }}
        end
    end
  end

  defp handle_stage_result(%StageExecutor.Result{status: :timeout} = result, state) do
    case TransitionEngine.next_stage(get_current_stage(state), result) do
      {:ok, :complete} ->
        broadcast_progress(state, :completed)
        {:noreply, %{state | status: :completed, completed_at: DateTime.utc_now()}}

      {:ok, next_stage_id} when is_atom(next_stage_id) ->
        Broadcast.stage_transition(
          state.session_id,
          state.current_stage,
          next_stage_id,
          "timeout"
        )

        new_state = %{state | current_stage: next_stage_id}
        broadcast_progress(new_state, :running)
        send(self(), :execute_current_stage)
        {:noreply, new_state}

      {:error, :no_transition_defined} ->
        broadcast_progress(state, :failed)
        {:noreply, %{state | status: :failed, failure_reason: result.error || "Stage timed out"}}
    end
  end

  defp get_current_stage(%__MODULE__{current_stage: nil}), do: nil

  defp get_current_stage(%__MODULE__{workflow_id: workflow_id, current_stage: stage_id}) do
    case WorkflowStore.get(workflow_id) do
      {:ok, workflow} -> Map.get(workflow.stages, stage_id)
      _ -> nil
    end
  end

  defp broadcast_progress(%__MODULE__{session_id: nil}, _status), do: :ok

  defp broadcast_progress(%__MODULE__{} = state, status) do
    total_stages =
      case WorkflowStore.get(state.workflow_id) do
        {:ok, workflow} -> length(workflow.stage_order || [])
        _ -> 0
      end

    Broadcast.workflow_progress(state.session_id, %{
      current_stage: state.current_stage,
      completed_count: length(state.execution_history),
      total_stages: total_stages,
      status: status
    })
  end

  defp validate_transition(from_status, to_status) do
    if to_status in Map.get(@valid_transitions, from_status, []) do
      :ok
    else
      {:error, {:invalid_transition, from_status, to_status}}
    end
  end
end
