defmodule Babysitter.SessionManager do
  @moduledoc """
  GenServer for managing agent sessions.

  Responsibilities:
  - Track active session IDs
  - Spawn/terminate Session processes via SessionSupervisor
  - Provide session lookup by ID
  - Delegate lifecycle operations to Session processes
  """

  use GenServer

  @type session_id :: String.t()

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def create_session(session_id, opts \\ []) do
    GenServer.call(__MODULE__, {:create_session, session_id, opts})
  end

  def get_session(session_id) do
    case Babysitter.Session.whereis(session_id) do
      nil ->
        {:error, :not_found}

      _pid ->
        try do
          Babysitter.Session.get_state(session_id)
        catch
          :exit, _ -> {:error, :not_found}
        end
    end
  end

  def list_sessions do
    GenServer.call(__MODULE__, :list_sessions)
  end

  def pause_session(session_id) do
    case Babysitter.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.Session.pause(session_id)
    end
  end

  def resume_session(session_id) do
    case Babysitter.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.Session.resume(session_id)
    end
  end

  def destroy_session(session_id) do
    GenServer.call(__MODULE__, {:destroy_session, session_id})
  end

  def intervene_session(session_id, action, opts \\ []) do
    case Babysitter.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.Session.intervene(session_id, action, opts)
    end
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  def append_output(session_id, output) do
    case Babysitter.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.Session.append_output(session_id, output)
    end
  end

  def get_output(session_id) do
    case Babysitter.Session.whereis(session_id) do
      nil -> {:error, :not_found}
      _pid -> Babysitter.Session.get_output(session_id)
    end
  end

  @impl true
  def init(_opts) do
    {:ok, %{session_ids: MapSet.new()}}
  end

  @impl true
  def handle_call({:create_session, session_id, opts}, _from, state) do
    if MapSet.member?(state.session_ids, session_id) do
      {:reply, {:error, :already_exists}, state}
    else
      spec = {Babysitter.Session, Keyword.put(opts, :id, session_id)}

      case DynamicSupervisor.start_child(Babysitter.SessionSupervisor, spec) do
        {:ok, _pid} ->
          {:ok, session} = Babysitter.Session.get_state(session_id)
          state = put_in(state, [:session_ids], MapSet.put(state.session_ids, session_id))
          {:reply, {:ok, session}, state}

        {:error, {:already_started, _pid}} ->
          {:reply, {:error, :already_exists}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call(:list_sessions, _from, state) do
    sessions =
      state.session_ids
      |> Enum.map(fn id ->
        case Babysitter.Session.get_state(id) do
          {:ok, session} -> session
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, sessions, state}
  end

  def handle_call({:destroy_session, session_id}, _from, state) do
    case Babysitter.Session.whereis(session_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        Babysitter.Session.stop(session_id)
        DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
        state = put_in(state, [:session_ids], MapSet.delete(state.session_ids, session_id))
        {:reply, :ok, state}
    end
  end

  def handle_call(:clear, _from, state) do
    for session_id <- state.session_ids do
      if pid = Babysitter.Session.whereis(session_id) do
        Babysitter.Session.stop(session_id)
        DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
      end
    end

    {:reply, :ok, %{session_ids: MapSet.new()}}
  end
end
