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
      {:ok, session} ->
        json(conn, %{session: session})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Session not found"})
    end
  end

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
