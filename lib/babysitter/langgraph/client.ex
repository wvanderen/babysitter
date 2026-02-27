defmodule Babysitter.LangGraph.Client do
  @moduledoc """
  Client for communicating with the LangGraph service.

  Provides functions for health checks, thread management, and run execution
  with automatic retry logic using exponential backoff.
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
