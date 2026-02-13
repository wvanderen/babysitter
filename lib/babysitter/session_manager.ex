defmodule Babysitter.SessionManager do
  @moduledoc """
  GenServer for managing agent sessions.

  Responsibilities:
  - Track active agent sessions
  - Provide session lookup by ID
  - Handle session lifecycle (create, destroy)
  """

  use GenServer

  @type session_id :: String.t()
  @type session :: %{
          id: session_id(),
          status: :starting | :running | :stopping | :stopped,
          started_at: DateTime.t(),
          pid: pid() | nil
        }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:create_session, session_id, opts})
  end

  def get_session(session_id) do
    GenServer.call(__MODULE__, {:get_session, session_id})
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  def destroy_session(session_id) do
    GenServer.call(__MODULE__, {:destroy_session, session_id})
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  @impl true
  def init(_opts) do
    state = %{
      sessions: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_session, session_id, opts}, _from, state) do
    session = %{
      id: session_id,
      status: :starting,
      started_at: DateTime.utc_now(),
      pid: Keyword.get(opts, :pid)
    }

    state = put_in(state, [:sessions, session_id], session)
    {:reply, {:ok, session}, state}
  end

  def handle_call({:get_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil -> {:reply, {:error, :not_found}, state}
      session -> {:reply, {:ok, session}, state}
    end
  end

  def handle_call(:list_sessions, _from, state) do
    sessions = Map.values(state.sessions)
    {:reply, sessions, state}
  end

  def handle_call({:destroy_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      session ->
        session = %{session | status: :stopped}
        state = put_in(state, [:sessions, session_id], session)
        {:reply, {:ok, session}, state}
    end
  end

  def handle_call(:clear, _from, _state) do
    {:reply, :ok, %{sessions: %{}}}
  end
end
