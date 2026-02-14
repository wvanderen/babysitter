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
        json(conn, %{session: session})

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
end
