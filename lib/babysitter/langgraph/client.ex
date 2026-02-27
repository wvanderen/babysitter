defmodule Babysitter.LangGraph.Client do
  @moduledoc """
  Client for communicating with the LangGraph service.

  Provides functions for health checks, thread management, and run execution
  with automatic retry logic using exponential backoff (1s, 2s, 4s delays).

  ## Configuration

  The client is configured via application environment:

      config :babysitter, Babysitter.LangGraph.Config,
        base_url: "http://127.0.0.1:8123",
        timeout: 30_000,
        max_retries: 3,
        base_delay_ms: 1000

  ## Usage Examples

  ### Health Check

      # Check if service is running
      {:ok, _response} = Babysitter.LangGraph.Client.health_check()

      # Boolean check
      if Babysitter.LangGraph.Client.healthy?(), do: :ok, else: :error

  ### Thread Management

      # Create a new thread
      {:ok, %Tesla.Env{body: %{"thread_id" => thread_id}}} =
        Babysitter.LangGraph.Client.create_thread()

      # Create with specific assistant
      {:ok, response} = Babysitter.LangGraph.Client.create_thread("my-assistant")

      # Get thread details
      {:ok, response} = Babysitter.LangGraph.Client.get_thread(thread_id)

  ### Run Lifecycle

      # Start a run with input
      {:ok, %Tesla.Env{body: %{"run_id" => run_id}}} =
        Babysitter.LangGraph.Client.create_run(thread_id, input: %{message: "Hello"})

      # Start with options
      {:ok, response} =
        Babysitter.LangGraph.Client.create_run(thread_id,
          assistant_id: "agent",
          input: %{query: "Search for X"},
          stream_mode: "values"
        )

      # Poll run status
      {:ok, %Tesla.Env{body: %{"status" => status}}} =
        Babysitter.LangGraph.Client.get_run_status(thread_id, run_id)

      # Check if interrupted
      {:ok, true} = Babysitter.LangGraph.Client.interrupted?(thread_id, run_id)

      # Cancel a run
      {:ok, _response} = Babysitter.LangGraph.Client.cancel_run(thread_id, run_id)

      # List all runs for a thread
      {:ok, %Tesla.Env{body: runs}} = Babysitter.LangGraph.Client.list_runs(thread_id)

  ### Interrupt/Resume Flow

      # Resume with a value
      {:ok, response} =
        Babysitter.LangGraph.Client.resume_run(thread_id, run_id, {:resume, %{"action" => "continue"}})

      # Approve and continue
      {:ok, response} = Babysitter.LangGraph.Client.resume_run(thread_id, run_id, :approve)

      # Reject and stop
      {:ok, response} = Babysitter.LangGraph.Client.resume_run(thread_id, run_id, :reject)

  ## Error Handling

  All functions return `{:ok, Tesla.Env.t()}` on success or `{:error, reason}` on failure.
  Functions automatically retry with exponential backoff (1s, 2s, 4s) up to max_retries.

  ## State Mapping

  | LangGraph Status | Description |
  |------------------|-------------|
  | `pending`        | Run is queued |
  | `running`        | Run is executing |
  | `interrupted`    | Run paused for input |
  | `completed`      | Run finished successfully |
  | `error`          | Run failed |
  | `cancelled`      | Run was cancelled |
  """

  use Tesla

  alias Babysitter.LangGraph.Config

  plug(Tesla.Middleware.BaseUrl, Config.base_url())
  plug(Tesla.Middleware.JSON)
  plug(Tesla.Middleware.Timeout, timeout: Config.timeout())

  @doc """
  Check if the LangGraph service is healthy.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec health_check() :: {:ok, Tesla.Env.t()} | {:error, term()}
  def health_check do
    with_retry(fn -> get("/info") end)
  end

  @doc """
  Create a new thread in the LangGraph service.

  Returns `{:ok, response}` with thread_id on success or `{:error, reason}` on failure.
  """
  @spec create_thread() :: {:ok, Tesla.Env.t()} | {:error, term()}
  def create_thread do
    with_retry(fn -> post("/threads", %{}) end)
  end

  @doc """
  Create a new thread with a specific assistant.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec create_thread(String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def create_thread(assistant_id) when is_binary(assistant_id) do
    with_retry(fn -> post("/threads", %{assistant_id: assistant_id}) end)
  end

  @doc """
  Get an existing thread by ID.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec get_thread(String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def get_thread(thread_id) when is_binary(thread_id) do
    with_retry(fn -> get("/threads/#{thread_id}") end)
  end

  @doc """
  Start a run on a thread.

  Returns `{:ok, response}` with run_id on success or `{:error, reason}` on failure.

  ## Options

    * `:assistant_id` - The assistant to use (default: "agent")
    * `:input` - Input payload for the run (default: %{})
    * `:stream_mode` - Streaming mode ("values", "messages", etc.)
    * `:config` - LangGraph configuration map
    * `:webhook` - Webhook URL for run completion

  """
  @spec create_run(String.t(), keyword() | map()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def create_run(thread_id, opts \\ [])

  def create_run(thread_id, opts) when is_binary(thread_id) and is_list(opts) do
    assistant_id = Keyword.get(opts, :assistant_id, "agent")
    input = Keyword.get(opts, :input, %{})
    stream_mode = Keyword.get(opts, :stream_mode)
    config = Keyword.get(opts, :config)
    webhook = Keyword.get(opts, :webhook)

    body =
      %{assistant_id: assistant_id, input: input}
      |> maybe_add(:stream_mode, stream_mode)
      |> maybe_add(:config, config)
      |> maybe_add(:webhook, webhook)

    with_retry(fn ->
      post("/threads/#{thread_id}/runs", body)
    end)
  end

  def create_run(thread_id, input) when is_binary(thread_id) and is_map(input) do
    with_retry(fn ->
      post("/threads/#{thread_id}/runs", %{assistant_id: "agent", input: input})
    end)
  end

  @doc """
  Get details of a specific run.

  Returns `{:ok, response}` with run details on success or `{:error, reason}` on failure.
  """
  @spec get_run(String.t(), String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def get_run(thread_id, run_id) when is_binary(thread_id) and is_binary(run_id) do
    with_retry(fn -> get("/threads/#{thread_id}/runs/#{run_id}") end)
  end

  @doc """
  Get the status of a run.

  Returns `{:ok, response}` with run status on success or `{:error, reason}` on failure.

  Possible statuses: pending, running, interrupted, completed, error, cancelled
  """
  @spec get_run_status(String.t(), String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def get_run_status(thread_id, run_id) when is_binary(thread_id) and is_binary(run_id) do
    with_retry(fn -> get("/threads/#{thread_id}/runs/#{run_id}/status") end)
  end

  @doc """
  Cancel a running run.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec cancel_run(String.t(), String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def cancel_run(thread_id, run_id) when is_binary(thread_id) and is_binary(run_id) do
    with_retry(fn -> delete("/threads/#{thread_id}/runs/#{run_id}") end)
  end

  @doc """
  List all runs for a thread.

  Returns `{:ok, response}` with list of runs on success or `{:error, reason}` on failure.
  """
  @spec list_runs(String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def list_runs(thread_id) when is_binary(thread_id) do
    with_retry(fn -> get("/threads/#{thread_id}/runs") end)
  end

  @doc """
  Get the state of a thread.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  @spec get_state(String.t()) :: {:ok, Tesla.Env.t()} | {:error, term()}
  def get_state(thread_id) when is_binary(thread_id) do
    with_retry(fn -> get("/threads/#{thread_id}/state") end)
  end

  @doc """
  Resume an interrupted run.

  Returns `{:ok, response}` on success or `{:error, reason}` on failure.

  ## Command Types

      * `{:resume, value}` - Resume with a specific value
      * `:approve` - Approve and continue the run
      * `:reject` - Reject and stop the run

  ## Examples

      # Resume with a value
      Client.resume_run("thread-123", "run-456", {:resume, %{"action" => "continue"}})

      # Approve and continue
      Client.resume_run("thread-123", "run-456", :approve)

      # Reject and stop
      Client.resume_run("thread-123", "run-456", :reject)

  """
  @spec resume_run(String.t(), String.t(), {:resume, term()} | :approve | :reject) ::
          {:ok, Tesla.Env.t()} | {:error, term()}
  def resume_run(thread_id, run_id, command)
      when is_binary(thread_id) and is_binary(run_id) do
    body = build_resume_command(command)

    with_retry(fn -> post("/threads/#{thread_id}/runs/#{run_id}", body) end)
  end

  @doc """
  Check if a run is in interrupted state.

  Returns `{:ok, true}` if the run is interrupted, `{:ok, false}` if not,
  or `{:error, reason}` on failure.
  """
  @spec interrupted?(String.t(), String.t()) :: {:ok, boolean()} | {:error, term()}
  def interrupted?(thread_id, run_id)
      when is_binary(thread_id) and is_binary(run_id) do
    case get_run_status(thread_id, run_id) do
      {:ok, %Tesla.Env{body: %{"status" => "interrupted"}}} -> {:ok, true}
      {:ok, %Tesla.Env{}} -> {:ok, false}
      error -> error
    end
  end

  defp build_resume_command(:approve), do: %{command: %{resume: "approved"}}
  defp build_resume_command(:reject), do: %{command: %{resume: "rejected"}}
  defp build_resume_command({:resume, value}), do: %{command: %{resume: value}}

  @doc """
  Execute a function with retry logic using exponential backoff.

  Retries up to max_retries times with exponential delay between attempts.
  Config values are read at runtime for dynamic configuration.
  """
  @spec with_retry((-> {:ok, term()} | {:error, term()}), non_neg_integer()) ::
          {:ok, term()} | {:error, term()}
  def with_retry(fun, attempt \\ 1) do
    max_retries = Config.max_retries()
    base_delay_ms = Config.base_delay_ms()

    case fun.() do
      {:ok, response} ->
        {:ok, response}

      {:error, _reason} when attempt < max_retries ->
        delay = trunc(base_delay_ms * :math.pow(2, attempt - 1))
        Process.sleep(delay)
        with_retry(fun, attempt + 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Check if the LangGraph service is reachable.

  Returns `true` if healthy, `false` otherwise.
  """
  @spec healthy?() :: boolean()
  def healthy? do
    case health_check() do
      {:ok, %Tesla.Env{status: status}} when status in 200..299 -> true
      _ -> false
    end
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
