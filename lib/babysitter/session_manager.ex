defmodule Babysitter.SessionManager do
  @moduledoc """
  GenServer for managing agent sessions with tmux integration.

  Responsibilities:
  - Track active agent sessions
  - Provide session lookup by ID
  - Handle session lifecycle (create, pause, resume, destroy)
  - Integrate with tmux for terminal sessions
  """

  use GenServer

  @type session_id :: String.t()
  @type session :: %{
          id: session_id(),
          status: :starting | :running | :paused | :stopping | :stopped,
          started_at: DateTime.t(),
          pid: pid() | nil,
          tmux_name: String.t() | nil
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

  def pause_session(session_id) do
    GenServer.call(__MODULE__, {:pause_session, session_id})
  end

  def resume_session(session_id) do
    GenServer.call(__MODULE__, {:resume_session, session_id})
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
    tmux_name = Keyword.get(opts, :tmux_name, "babysitter-#{session_id}")

    case Babysitter.Tmux.create_session(tmux_name) do
      :ok ->
        session = %{
          id: session_id,
          status: :running,
          started_at: DateTime.utc_now(),
          pid: Keyword.get(opts, :pid),
          tmux_name: tmux_name
        }

        state = put_in(state, [:sessions, session_id], session)
        {:reply, {:ok, session}, state}

      {:error, reason} ->
        {:reply, {:error, {:tmux_error, reason}}, state}
    end
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

  def handle_call({:pause_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :paused} ->
        {:reply, {:error, :already_paused}, state}

      %{tmux_name: tmux_name} = session ->
        Babysitter.Tmux.send_keys(tmux_name, "\x1A")
        session = %{session | status: :paused}
        state = put_in(state, [:sessions, session_id], session)
        {:reply, {:ok, session}, state}
    end
  end

  def handle_call({:resume_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :running} ->
        {:reply, {:error, :not_paused}, state}

      %{tmux_name: tmux_name} = session ->
        Babysitter.Tmux.send_keys(tmux_name, "\x1A")
        session = %{session | status: :running}
        state = put_in(state, [:sessions, session_id], session)
        {:reply, {:ok, session}, state}
    end
  end

  def handle_call({:destroy_session, session_id}, _from, state) do
    case Map.get(state.sessions, session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{tmux_name: tmux_name} = _session ->
        Babysitter.Tmux.kill_session(tmux_name)
        state = update_in(state, [:sessions], &Map.delete(&1, session_id))
        {:reply, :ok, state}
    end
  end

  def handle_call(:clear, _from, state) do
    for {_id, %{tmux_name: tmux_name}} <- state.sessions do
      Babysitter.Tmux.kill_session(tmux_name)
    end

    {:reply, :ok, %{sessions: %{}}}
  end
end
