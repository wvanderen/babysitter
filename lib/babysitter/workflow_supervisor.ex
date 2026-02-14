defmodule Babysitter.WorkflowSupervisor do
  @moduledoc """
  Supervisor for running workflow instances.

  Provides:
  - Dynamic supervision of WorkflowInstance processes
  - Graceful crash handling with restart strategies
  - Instance lifecycle management (create, start, stop)
  - Instance lookup and enumeration

  ## Crash Handling

  Workflow instances use :transient restart strategy, meaning they
  will be restarted if they crash abnormally (not :normal or :shutdown).
  State is persisted via Babysitter.State.Persistence before termination.

  ## Example

      # Start a new workflow instance
      {:ok, instance_id} = WorkflowSupervisor.start_workflow("feature-implementation",
        session_id: "sess-123",
        variables: %{"issue_id" => "td-123"}
      )

      # Check status
      {:ok, status} = WorkflowSupervisor.get_status(instance_id)

      # Pause/resume
      :ok = WorkflowSupervisor.pause(instance_id)
      :ok = WorkflowSupervisor.resume(instance_id)

      # Stop (terminates the process)
      :ok = WorkflowSupervisor.stop_workflow(instance_id)
  """

  @type instance_id :: String.t()
  @type workflow_id :: String.t()
  @type start_opts :: [
          session_id: String.t(),
          variables: map(),
          max_retries: non_neg_integer()
        ]

  @doc """
  Start a new workflow instance.

  Creates and starts a WorkflowInstance process under supervision.

  ## Options
    * `:session_id` - Required. The session to execute workflow in.
    * `:variables` - Variables for prompt interpolation.
    * `:max_retries` - Max retry attempts per stage (default: 3).
    * `:auto_start` - Whether to auto-start execution (default: true).

  ## Returns
    * `{:ok, instance_id}` - Instance started successfully
    * `{:error, reason}` - Failed to start
  """
  @spec start_workflow(workflow_id(), start_opts()) ::
          {:ok, instance_id()} | {:error, term()}
  def start_workflow(workflow_id, opts \\ []) do
    with {:ok, _workflow} <- Babysitter.WorkflowStore.get(workflow_id) do
      instance_id = generate_instance_id()
      session_id = Keyword.get(opts, :session_id)
      variables = Keyword.get(opts, :variables, %{})
      max_retries = Keyword.get(opts, :max_retries, 3)
      auto_start = Keyword.get(opts, :auto_start, true)

      spec =
        {Babysitter.WorkflowInstance,
         id: instance_id,
         workflow_id: workflow_id,
         session_id: session_id,
         variables: variables,
         max_retries: max_retries}

      case DynamicSupervisor.start_child(Babysitter.WorkflowSupervisor, spec) do
        {:ok, _pid} ->
          if auto_start do
            Babysitter.WorkflowInstance.start(instance_id, session_id: session_id)
          end

          {:ok, instance_id}

        {:error, {:already_started, _pid}} ->
          {:error, :already_exists}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Create a workflow instance without starting execution.

  Use this when you need to set up the instance before running.
  """
  @spec create_workflow(workflow_id(), start_opts()) ::
          {:ok, instance_id()} | {:error, term()}
  def create_workflow(workflow_id, opts \\ []) do
    start_workflow(workflow_id, Keyword.put(opts, :auto_start, false))
  end

  @doc """
  Begin execution of a created workflow instance.
  """
  @spec run_workflow(instance_id(), keyword()) :: :ok | {:error, term()}
  def run_workflow(instance_id, opts \\ []) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.start(instance_id, opts)
    end
  end

  @doc """
  Pause a running workflow instance.
  """
  @spec pause(instance_id()) :: :ok | {:error, term()}
  def pause(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.pause(instance_id)
    end
  end

  @doc """
  Resume a paused workflow instance.
  """
  @spec resume(instance_id()) :: :ok | {:error, term()}
  def resume(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.resume(instance_id)
    end
  end

  @doc """
  Stop a workflow instance and remove it from supervision.
  """
  @spec stop_workflow(instance_id()) :: :ok | {:error, term()}
  def stop_workflow(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil ->
        {:error, :not_found}

      pid ->
        Babysitter.WorkflowInstance.stop(instance_id)
        DynamicSupervisor.terminate_child(Babysitter.WorkflowSupervisor, pid)
        :ok
    end
  end

  @doc """
  Get the current state of a workflow instance.
  """
  @spec get_state(instance_id()) :: {:ok, map()} | {:error, term()}
  def get_state(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        try do
          Babysitter.WorkflowInstance.get_state(instance_id)
        catch
          :exit, _ -> {:error, :not_found}
        end
    end
  end

  @doc """
  Get the status of a workflow instance.
  """
  @spec get_status(instance_id()) :: {:ok, atom()} | {:error, term()}
  def get_status(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.get_status(instance_id)
    end
  end

  @doc """
  Get the execution history of a workflow instance.
  """
  @spec get_history(instance_id()) :: {:ok, [map()]} | {:error, term()}
  def get_history(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.get_history(instance_id)
    end
  end

  @doc """
  Set a variable on a workflow instance.
  """
  @spec set_variable(instance_id(), term(), term()) :: :ok | {:error, term()}
  def set_variable(instance_id, key, value) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        Babysitter.WorkflowInstance.set_variable(instance_id, key, value)
        :ok
    end
  end

  @doc """
  Set multiple variables on a workflow instance.
  """
  @spec set_variables(instance_id(), map()) :: :ok | {:error, term()}
  def set_variables(instance_id, vars) when is_map(vars) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        Babysitter.WorkflowInstance.set_variables(instance_id, vars)
        :ok
    end
  end

  @doc """
  Manually fail a workflow instance.
  """
  @spec fail(instance_id(), String.t() | nil) :: :ok | {:error, term()}
  def fail(instance_id, reason \\ nil) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.fail(instance_id, reason)
    end
  end

  @doc """
  Escalate a workflow instance.
  """
  @spec escalate(instance_id(), String.t() | nil) :: :ok | {:error, term()}
  def escalate(instance_id, reason \\ nil) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.escalate(instance_id, reason)
    end
  end

  @doc """
  Retry a failed workflow instance.
  """
  @spec retry(instance_id()) :: :ok | {:error, term()}
  def retry(instance_id) do
    case Babysitter.WorkflowInstance.whereis(instance_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.WorkflowInstance.retry(instance_id)
    end
  end

  @doc """
  List all active workflow instances.

  Returns a list of {instance_id, pid, status} tuples.
  """
  @spec list_workflows() :: [{instance_id(), pid(), atom()}]
  def list_workflows do
    Registry.select(Babysitter.WorkflowRegistry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {instance_id, pid} ->
      status =
        case Babysitter.WorkflowInstance.get_status(instance_id) do
          {:ok, s} -> s
          _ -> :unknown
        end

      {instance_id, pid, status}
    end)
  end

  @doc """
  Count active workflow instances.
  """
  @spec count_workflows() :: non_neg_integer()
  def count_workflows do
    DynamicSupervisor.count_children(Babysitter.WorkflowSupervisor)[:active] || 0
  end

  @doc """
  Check if a workflow instance exists.
  """
  @spec exists?(instance_id()) :: boolean()
  def exists?(instance_id) do
    Babysitter.WorkflowInstance.whereis(instance_id) != nil
  end

  @doc """
  Stop all workflow instances.

  Use with caution - this terminates all running workflows.
  """
  @spec stop_all() :: :ok
  def stop_all do
    for {instance_id, pid, _status} <- list_workflows() do
      Babysitter.WorkflowInstance.stop(instance_id)
      DynamicSupervisor.terminate_child(Babysitter.WorkflowSupervisor, pid)
    end

    :ok
  end

  @doc """
  Restart a workflow instance after crash recovery.

  This is called automatically when a WorkflowInstance process
  restarts after an abnormal termination.
  """
  @spec recover_workflow(instance_id()) :: {:ok, instance_id()} | {:error, term()}
  def recover_workflow(instance_id) do
    case Babysitter.State.Persistence.load_workflow_state(instance_id) do
      {:ok, saved_state} ->
        opts = [
          workflow_id: saved_state.workflow_id,
          session_id: saved_state.session_id,
          variables: saved_state.variables,
          max_retries: saved_state.max_retries,
          auto_start: false
        ]

        with {:ok, _id} <- start_workflow(saved_state.workflow_id, opts) do
          Babysitter.WorkflowInstance.start(instance_id, session_id: saved_state.session_id)
        end

      {:error, :not_found} ->
        {:error, :no_saved_state}
    end
  end

  defp generate_instance_id do
    :crypto.strong_rand_bytes(8)
    |> Base.encode16(case: :lower)
    |> then(&("wf-" <> &1))
  end
end
