defmodule BabysitterWeb.SessionController do
  use Phoenix.Controller, formats: [:html, :json]

  alias Babysitter.SessionManager

  def index(conn, _params) do
    sessions = SessionManager.list_sessions()
    json(conn, %{sessions: sessions})
  end

  def show(conn, %{"id" => id}) do
    case SessionManager.get_session(id) do
      {:ok, session} ->
        response = Map.put(session_data(session), :workflow_instance, find_workflow_instance(id))
        json(conn, %{session: response})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})
    end
  end

  def create(conn, %{"session" => session_params}) do
    id = Map.get(session_params, "id", generate_session_id())
    opts = build_session_opts(session_params)

    case SessionManager.create_session(id, opts) do
      {:ok, session} ->
        conn
        |> put_status(:created)
        |> json(%{session: session})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def delete(conn, %{"id" => id}) do
    case SessionManager.destroy_session(id) do
      :ok ->
        json(conn, %{status: "deleted"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})
    end
  end

  def pause(conn, %{"id" => id}) do
    case SessionManager.pause_session(id) do
      {:ok, session} ->
        json(conn, %{session: session})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  def resume(conn, %{"id" => id}) do
    case SessionManager.resume_session(id) do
      {:ok, session} ->
        json(conn, %{session: session})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: inspect(reason)})
    end
  end

  @valid_intervention_actions [:retry, :restart, :escalate, :skip]

  def intervene(conn, %{"id" => id, "action" => action}) do
    case parse_intervention_action(action) do
      {:ok, action_atom} ->
        reason = Map.get(conn.params, "reason")
        opts = if reason, do: [reason: reason], else: []

        case SessionManager.intervene_session(id, action_atom, opts) do
          {:ok, result} ->
            json(conn, %{status: "ok", action: action, result: result})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Session not found"})

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: inspect(reason)})
        end

      {:error, :invalid_action} ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error:
            "Invalid action: #{action}. Valid actions: #{Enum.join(@valid_intervention_actions, ", ")}"
        })
    end
  end

  def intervene(conn, %{"id" => _id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: action"})
  end

  defp parse_intervention_action(action) when is_binary(action) do
    try do
      atom = String.to_existing_atom(action)

      if atom in @valid_intervention_actions do
        {:ok, atom}
      else
        {:error, :invalid_action}
      end
    rescue
      ArgumentError -> {:error, :invalid_action}
    end
  end

  defp parse_intervention_action(_), do: {:error, :invalid_action}

  defp generate_session_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp build_session_opts(params) do
    if pid = Map.get(params, "pid") do
      [pid: pid]
    else
      []
    end
  end

  defp session_data(session) do
    %{
      id: session.id,
      status: session.status,
      tmux_name: session.tmux_name,
      started_at: session.started_at,
      metadata: session.metadata,
      failure_reason: session.failure_reason,
      escalation_reason: session.escalation_reason,
      validation_results: session.validation_results
    }
  end

  defp find_workflow_instance(session_id) do
    Babysitter.WorkflowSupervisor.list_workflows()
    |> Enum.find_value(fn {instance_id, _pid, _status} ->
      case Babysitter.WorkflowSupervisor.get_state(instance_id) do
        {:ok, state} when state.session_id == session_id ->
          %{
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

        _ ->
          nil
      end
    end)
  end
end
