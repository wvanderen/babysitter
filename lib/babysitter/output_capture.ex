defmodule Babysitter.OutputCapture do
  @moduledoc "Real-time output capture from tmux sessions using pipe-pane"
  use GenServer
  alias Babysitter.Tmux

  @enforce_keys [:id, :session_name]
  defstruct [
    :id,
    :session_name,
    :pipe_file,
    :reader_pid,
    status: :initializing,
    started_at: nil,
    output_buffer: "",
    buffer_size: 0,
    max_buffer_size: 50_000,
    subscribers: []
  ]

  @default_pipe_dir "/tmp/babysitter-pipes"
  @default_max_buffer 50_000
  @read_chunk_size 4096

  def start_link(opts) do
    id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  def via_tuple(id), do: {:via, Registry, {Babysitter.OutputCaptureRegistry, id}}

  def whereis(id) do
    case Registry.lookup(Babysitter.OutputCaptureRegistry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp safe_call(id, message) do
    case whereis(id) do
      nil ->
        {:error, :not_found}

      pid ->
        try do
          GenServer.call(pid, message)
        catch
          :exit, {:noproc, _} -> {:error, :not_found}
          :exit, {:shutdown, _} -> {:error, :shutdown}
          :exit, _ -> {:error, :process_error}
        end
    end
  end

  @spec start_capture(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_capture(opts) do
    session_name = Keyword.fetch!(opts, :session_name)

    unless Tmux.session_exists?(session_name) do
      {:error, :session_not_found}
    else
      case start_link(opts) do
        {:ok, pid} -> {:ok, pid}
        {:error, reason} -> {:error, reason}
        {:ignore} -> {:error, :ignored}
      end
    end
  end

  @spec stop_capture(String.t()) :: :ok | {:error, term()}
  def stop_capture(id), do: safe_call(id, :stop)

  @spec pause(String.t()) :: :ok | {:error, term()}
  def pause(id), do: safe_call(id, :pause)

  @spec resume(String.t()) :: :ok | {:error, term()}
  def resume(id), do: safe_call(id, :resume)

  @spec get_output(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_output(id), do: safe_call(id, :get_output)

  @spec clear_buffer(String.t()) :: :ok | {:error, term()}
  def clear_buffer(id), do: safe_call(id, :clear_buffer)

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(id), do: safe_call(id, {:subscribe, self()})

  @spec unsubscribe(String.t()) :: :ok | {:error, term()}
  def unsubscribe(id), do: safe_call(id, {:unsubscribe, self()})

  @spec get_state(String.t()) :: {:ok, term()} | {:error, term()}
  def get_state(id), do: safe_call(id, :get_state)

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    session_name = Keyword.fetch!(opts, :session_name)
    max_buffer = Keyword.get(opts, :max_buffer_size, @default_max_buffer)
    pipe_dir = Keyword.get(opts, :pipe_dir, @default_pipe_dir)

    with :ok <- ensure_pipe_dir(pipe_dir),
         {:ok, pipe_file} <- create_pipe_file(id, pipe_dir),
         :ok <- setup_pipe_pane(session_name, pipe_file),
         {:ok, reader_pid} <- start_reader(pipe_file, self()) do
      {:ok,
       %__MODULE__{
         id: id,
         session_name: session_name,
         pipe_file: pipe_file,
         reader_pid: reader_pid,
         status: :running,
         started_at: DateTime.utc_now(),
         max_buffer_size: max_buffer
       }}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:stop, _from, state) do
    cleanup(state)
    {:stop, :normal, :ok, %{state | status: :stopped, reader_pid: nil}}
  end

  def handle_call(:pause, _from, state) do
    if state.reader_pid && Process.alive?(state.reader_pid), do: send(state.reader_pid, :pause)
    {:reply, :ok, %{state | status: :paused}}
  end

  def handle_call(:resume, _from, state) do
    if state.reader_pid && Process.alive?(state.reader_pid), do: send(state.reader_pid, :resume)
    {:reply, :ok, %{state | status: :running}}
  end

  def handle_call(:get_output, _from, state), do: {:reply, {:ok, state.output_buffer}, state}

  def handle_call(:clear_buffer, _from, state),
    do: {:reply, :ok, %{state | output_buffer: "", buffer_size: 0}}

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: [pid | state.subscribers]}}
  end

  def handle_call({:unsubscribe, pid}, _from, state),
    do: {:reply, :ok, %{state | subscribers: List.delete(state.subscribers, pid)}}

  def handle_call(:get_state, _from, state), do: {:reply, {:ok, state}, state}

  @impl true
  def handle_info({:output_chunk, chunk}, state) do
    new_buffer = append_to_buffer(state.output_buffer, chunk, state.max_buffer_size)
    broadcast_output(state.subscribers, state.id, chunk)
    {:noreply, %{state | output_buffer: new_buffer, buffer_size: byte_size(new_buffer)}}
  end

  def handle_info({:reader_exit, reason}, state) do
    unless reason == :normal,
      do: require(Logger) && Logger.warning("Output capture reader exited: #{inspect(reason)}")

    {:noreply, %{state | reader_pid: nil}}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state),
    do: {:noreply, %{state | subscribers: List.delete(state.subscribers, pid)}}

  @impl true
  def terminate(_reason, state), do: cleanup(state)

  defp ensure_pipe_dir(dir) do
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:pipe_dir_error, reason}}
    end
  end

  defp create_pipe_file(id, pipe_dir) do
    pipe_file = Path.join(pipe_dir, "capture-#{id}.pipe")

    case File.touch(pipe_file) do
      :ok -> {:ok, pipe_file}
      {:error, reason} -> {:error, {:pipe_file_error, reason}}
    end
  end

  defp setup_pipe_pane(session_name, pipe_file) do
    if not Tmux.session_exists?(session_name) do
      {:error, :session_not_found}
    else
      case Tmux.pipe_pane(session_name, pipe_file) do
        :ok -> :ok
        {:error, reason} -> {:error, {:tmux_pipe_error, reason}}
      end
    end
  end

  defp start_reader(pipe_file, parent) do
    reader_fn = fn -> reader_loop(pipe_file, parent) end

    case Task.start(reader_fn) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, {:reader_start_error, reason}}
    end
  end

  defp reader_loop(pipe_file, parent) do
    case File.open(pipe_file, [:read, :binary, :raw]) do
      {:ok, file} ->
        do_reader_loop(file, parent)
        File.close(file)

      {:error, reason} ->
        send(parent, {:reader_exit, {:file_open_error, reason}})
    end
  end

  defp do_reader_loop(file, parent) do
    receive do
      :pause ->
        receive do
          :resume -> do_reader_loop(file, parent)
        after
          :infinity -> :ok
        end
    after
      0 -> :ok
    end

    case :file.read(file, @read_chunk_size) do
      {:ok, data} when byte_size(data) > 0 ->
        send(parent, {:output_chunk, data})
        do_reader_loop(file, parent)

      {:ok, _} ->
        Process.sleep(50)
        do_reader_loop(file, parent)

      :eof ->
        Process.sleep(100)
        do_reader_loop(file, parent)

      {:error, reason} ->
        send(parent, {:reader_exit, {:read_error, reason}})
    end
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

  defp broadcast_output(subscribers, capture_id, chunk) do
    Enum.each(subscribers, &send(&1, {:output_capture, capture_id, chunk}))
  end

  defp cleanup(state) do
    if state.session_name && Tmux.session_exists?(state.session_name),
      do: Tmux.pipe_pane(state.session_name, nil)

    if state.reader_pid && Process.alive?(state.reader_pid),
      do: Process.exit(state.reader_pid, :shutdown)

    if state.pipe_file, do: File.rm(state.pipe_file)
  end
end
