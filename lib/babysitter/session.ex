defmodule Babysitter.Session do
  @moduledoc """
  GenServer representing a single agent session.

  Each session has its own process holding:
  - Session state and metadata
  - Tmux session reference
  - Output buffer for capturing agent output
  """

  use GenServer

  @type status :: :initializing | :running | :paused | :stopping | :stopped
  @type session_id :: String.t()

  @derive {Jason.Encoder, only: [:id, :status, :tmux_name, :started_at, :metadata]}
  @type t :: %__MODULE__{
          id: session_id(),
          status: status(),
          tmux_name: String.t() | nil,
          started_at: DateTime.t() | nil,
          output_buffer: String.t(),
          buffer_size: non_neg_integer(),
          max_buffer_size: non_neg_integer(),
          metadata: map()
        }

  @enforce_keys [:id]
  defstruct [
    :id,
    :tmux_name,
    status: :initializing,
    started_at: nil,
    output_buffer: "",
    buffer_size: 0,
    max_buffer_size: 100_000,
    metadata: %{}
  ]

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    name = via_tuple(id)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def via_tuple(id) do
    {:via, Registry, {Babysitter.SessionRegistry, id}}
  end

  def whereis(id) do
    case Registry.lookup(Babysitter.SessionRegistry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def get_state(id) do
    GenServer.call(via_tuple(id), :get_state)
  end

  def get_status(id) do
    GenServer.call(via_tuple(id), :get_status)
  end

  def get_output(id) do
    GenServer.call(via_tuple(id), :get_output)
  end

  def append_output(id, output) do
    GenServer.cast(via_tuple(id), {:append_output, output})
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

  def capture_tmux_output(id) do
    GenServer.call(via_tuple(id), :capture_tmux_output)
  end

  def clear_buffer(id) do
    GenServer.call(via_tuple(id), :clear_buffer)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    tmux_name = Keyword.get(opts, :tmux_name, "babysitter-#{id}")
    max_buffer = Keyword.get(opts, :max_buffer_size, 100_000)
    metadata = Keyword.get(opts, :metadata, %{})

    case Babysitter.Tmux.create_session(tmux_name) do
      :ok ->
        state = %__MODULE__{
          id: id,
          tmux_name: tmux_name,
          status: :running,
          started_at: DateTime.utc_now(),
          max_buffer_size: max_buffer,
          metadata: metadata
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, {:tmux_error, reason}}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(:get_status, _from, state) do
    {:reply, {:ok, state.status}, state}
  end

  def handle_call(:get_output, _from, state) do
    {:reply, {:ok, state.output_buffer}, state}
  end

  def handle_call(:pause, _from, state) do
    case state.status do
      :paused ->
        {:reply, {:error, :already_paused}, state}

      :running ->
        Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
        {:reply, {:ok, :paused}, %{state | status: :paused}}

      _ ->
        {:reply, {:error, :invalid_status}, state}
    end
  end

  def handle_call(:resume, _from, state) do
    case state.status do
      :running ->
        {:reply, {:error, :not_paused}, state}

      :paused ->
        Babysitter.Tmux.send_keys(state.tmux_name, "\x1A")
        {:reply, {:ok, :running}, %{state | status: :running}}

      _ ->
        {:reply, {:error, :invalid_status}, state}
    end
  end

  def handle_call(:stop, _from, state) do
    if state.tmux_name do
      Babysitter.Tmux.kill_session(state.tmux_name)
    end

    {:reply, :ok, %{state | status: :stopped, tmux_name: nil}}
  end

  def handle_call(:capture_tmux_output, _from, state) do
    case Babysitter.Tmux.capture_pane(state.tmux_name) do
      output when is_binary(output) ->
        {:reply, {:ok, output}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:clear_buffer, _from, state) do
    {:reply, :ok, %{state | output_buffer: "", buffer_size: 0}}
  end

  @impl true
  def handle_cast({:append_output, output}, state) do
    new_buffer = append_to_buffer(state.output_buffer, output, state.max_buffer_size)
    new_size = byte_size(new_buffer)
    {:noreply, %{state | output_buffer: new_buffer, buffer_size: new_size}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.tmux_name && Babysitter.Tmux.session_exists?(state.tmux_name) do
      Babysitter.Tmux.kill_session(state.tmux_name)
    end

    :ok
  end

  defp append_to_buffer(buffer, new_data, max_size) do
    combined = buffer <> new_data

    if byte_size(combined) > max_size do
      drop_bytes = byte_size(combined) - max_size
      binary_part(combined, drop_bytes, max_size)
    else
      combined
    end
  end
end
