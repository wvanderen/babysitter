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
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to start workflow", details: inspect(reason)})
        end

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Workflow not found"})
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
