defmodule Babysitter.LangGraph.ClientTest do
  use ExUnit.Case, async: false

  alias Babysitter.LangGraph.Client

  defmodule MockAdapter do
    @behaviour Tesla.Adapter

    @impl true
    def call(%Tesla.Env{} = env, _opts) do
      url = env.url

      cond do
        String.contains?(url, "/info") ->
          {:ok, %Tesla.Env{env | status: 200, body: %{"status" => "ok"}}}

        String.contains?(url, "/threads") && env.method == :post &&
            not String.contains?(url, "/runs") ->
          thread_id =
            "thread-" <> (:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower))

          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"thread_id" => thread_id, "assistant_id" => "agent"}
           }}

        String.contains?(url, "/thread-test/runs") && env.method == :post ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"run_id" => "run-test", "status" => "pending"}
           }}

        String.contains?(url, "/thread-test/state") && env.method == :get ->
          {:ok, %Tesla.Env{env | status: 200, body: %{"values" => %{}}}}

        String.contains?(url, "/thread-test/runs/run-test") && env.method == :get &&
            String.contains?(url, "/status") ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"run_id" => "run-test", "status" => "running"}
           }}

        String.contains?(url, "/thread-test/runs/run-test") && env.method == :get &&
            not String.contains?(url, "/status") ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{
                 "run_id" => "run-test",
                 "thread_id" => "thread-test",
                 "status" => "pending"
               }
           }}

        String.contains?(url, "/thread-test/runs/run-test") && env.method == :delete ->
          {:ok, %Tesla.Env{env | status: 200, body: %{"status" => "cancelled"}}}

        String.contains?(url, "/thread-test/runs") && env.method == :get ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: [
                 %{"run_id" => "run-1", "status" => "completed"},
                 %{"run_id" => "run-2", "status" => "running"}
               ]
           }}

        String.contains?(url, "/thread-test") && env.method == :get &&
          not String.contains?(url, "/state") && not String.contains?(url, "/runs") ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"thread_id" => "thread-test", "status" => "idle"}
           }}

        true ->
          {:ok, %Tesla.Env{env | status: 404, body: %{"error" => "not found"}}}
      end
    end
  end

  def mock_client do
    Tesla.client(
      [
        {Tesla.Middleware.BaseUrl, "http://127.0.0.1:8123"},
        Tesla.Middleware.JSON
      ],
      MockAdapter
    )
  end

  describe "health_check/0" do
    test "returns ok when service is healthy" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/info")

      assert response.status == 200
      assert response.body["status"] == "ok"
    end
  end

  describe "create_thread/0" do
    test "creates a new thread" do
      client = mock_client()
      {:ok, response} = Tesla.post(client, "/threads", %{})

      assert response.status == 200
      assert response.body["thread_id"] != nil
    end
  end

  describe "get_thread/1" do
    test "gets an existing thread" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test")

      assert response.status == 200
      assert response.body["thread_id"] == "thread-test"
    end
  end

  describe "create_run/2" do
    test "creates a run on a thread" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-test/runs", %{assistant_id: "agent", input: %{}})

      assert response.status == 200
      assert response.body["run_id"] != nil
    end

    test "creates a run with custom assistant_id" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-test/runs", %{
          assistant_id: "custom-agent",
          input: %{}
        })

      assert response.status == 200
    end
  end

  describe "get_state/1" do
    test "gets thread state" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/state")

      assert response.status == 200
      assert response.body["values"] != nil
    end
  end

  describe "get_run/2" do
    test "gets run details" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/runs/run-test")

      assert response.status == 200
      assert response.body["run_id"] == "run-test"
      assert response.body["thread_id"] == "thread-test"
    end
  end

  describe "get_run_status/2" do
    test "gets run status" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/runs/run-test/status")

      assert response.status == 200
      assert response.body["status"] == "running"
    end
  end

  describe "cancel_run/2" do
    test "cancels a run" do
      client = mock_client()
      {:ok, response} = Tesla.delete(client, "/threads/thread-test/runs/run-test")

      assert response.status == 200
      assert response.body["status"] == "cancelled"
    end
  end

  describe "list_runs/1" do
    test "lists all runs for a thread" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/runs")

      assert response.status == 200
      assert is_list(response.body)
      assert length(response.body) == 2
    end
  end

  describe "with_retry/2" do
    test "returns success on first attempt" do
      result = Client.with_retry(fn -> {:ok, :success} end)
      assert result == {:ok, :success}
    end

    test "retries on failure and succeeds" do
      attempts = :counters.new(1, [:atomics])

      result =
        Client.with_retry(fn ->
          :counters.add(attempts, 1, 1)
          count = :counters.get(attempts, 1)

          if count < 2 do
            {:error, :temporary_failure}
          else
            {:ok, :success}
          end
        end)

      assert result == {:ok, :success}
      assert :counters.get(attempts, 1) == 2
    end

    test "returns error after max retries" do
      attempts = :counters.new(1, [:atomics])

      result =
        Client.with_retry(fn ->
          :counters.add(attempts, 1, 1)
          {:error, :permanent_failure}
        end)

      assert result == {:error, :permanent_failure}
      assert :counters.get(attempts, 1) == 3
    end
  end
end
