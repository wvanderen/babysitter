defmodule BabysitterWeb.WorkflowController do
  use Phoenix.Controller, formats: [:html, :json]

  def index(conn, _params) do
    workflows = list_workflows()
    json(conn, %{workflows: workflows})
  end

  def show(conn, %{"id" => id}) do
    case get_workflow(id) do
      {:ok, workflow} ->
        json(conn, %{workflow: workflow})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})
    end
  end

  def create(conn, %{"workflow" => workflow_params}) do
    id = Map.get(workflow_params, "id", generate_workflow_id())
    name = Map.get(workflow_params, "name", "Untitled Workflow")
    stages = Map.get(workflow_params, "stages", [])

    workflow = %{
      id: id,
      name: name,
      stages: stages,
      status: :created,
      created_at: DateTime.utc_now()
    }

    store_workflow(workflow)
    json(conn, %{workflow: workflow})
  end

  def execute(conn, %{"workflow_id" => id} = params) do
    case get_workflow(id) do
      {:ok, _workflow} ->
        session_id = Map.get(params, "session_id", generate_session_id())
        variables = build_variables(params)
        issue_id = Map.get(params, "issue_id")

        final_vars =
          if issue_id do
            Map.put(variables, "issue_id", issue_id)
          else
            variables
          end

        case Babysitter.SessionManager.create_session(session_id,
               issue_id: issue_id,
               variables: final_vars
             ) do
          {:ok, _pid} ->
            opts = [
              session_id: session_id,
              variables: final_vars
            ]

            case Babysitter.WorkflowSupervisor.start_workflow(id, opts) do
              {:ok, instance_id} ->
                json(conn, %{
                  workflow_id: id,
                  instance_id: instance_id,
                  session_id: session_id,
                  status: :started
                })

              {:error, reason} ->
                Babysitter.SessionManager.destroy_session(session_id)

                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to start workflow", details: inspect(reason)})
            end

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to create session", details: inspect(reason)})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})
    end
  end

  def show_instance(conn, %{"workflow_id" => workflow_id, "instance_id" => instance_id}) do
    with {:ok, _workflow} <- get_workflow(workflow_id),
         {:ok, state} <- Babysitter.WorkflowSupervisor.get_state(instance_id) do
      json(conn, %{
        instance: %{
          id: state.id,
          workflow_id: state.workflow_id,
          session_id: state.session_id,
          status: state.status,
          current_stage: state.current_stage,
          started_at: state.started_at,
          completed_at: state.completed_at,
          failure_reason: state.failure_reason,
          escalation_reason: state.escalation_reason,
          retry_count: state.retry_count,
          max_retries: state.max_retries,
          execution_history: state.execution_history,
          variables: state.variables
        }
      })
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow or instance not found"})
    end
  end

  def instance_history(conn, %{"workflow_id" => workflow_id, "instance_id" => instance_id}) do
    with {:ok, _workflow} <- get_workflow(workflow_id),
         {:ok, history} <- Babysitter.WorkflowSupervisor.get_history(instance_id) do
      json(conn, %{history: history})
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow or instance not found"})
    end
  end

  defp list_workflows do
    Babysitter.WorkflowStore.list()
  end

  defp get_workflow(id) do
    Babysitter.WorkflowStore.get(id)
  end

  defp store_workflow(workflow) do
    Babysitter.WorkflowStore.put(workflow)
  end

  defp generate_workflow_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp generate_session_id do
    "sess-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp build_variables(params) do
    case Map.get(params, "variables") do
      vars when is_map(vars) -> vars
      _ -> %{}
    end
  end
end
