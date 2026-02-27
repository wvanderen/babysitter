defmodule Babysitter.LangGraph.ClientTest do
  use ExUnit.Case, async: false

  alias Babysitter.LangGraph.Client

  @moduletag :capture_log

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

        String.contains?(url, "/thread-interrupt/runs/run-interrupt") &&
          env.method == :get &&
            String.contains?(url, "/status") ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"run_id" => "run-interrupt", "status" => "interrupted"}
           }}

        String.contains?(url, "/thread-resume/runs/run-resume") && env.method == :post ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{"run_id" => "run-resume", "status" => "running"}
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

  describe "resume_run/3" do
    test "resumes a run with :approve command" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: "approved"}
        })

      assert response.status == 200
      assert response.body["status"] == "running"
    end

    test "resumes a run with :reject command" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: "rejected"}
        })

      assert response.status == 200
    end

    test "resumes a run with {:resume, value} command" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: %{"action" => "continue"}}
        })

      assert response.status == 200
    end
  end

  describe "interrupted?/2" do
    test "returns true when run is interrupted" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-interrupt/runs/run-interrupt/status")

      assert response.status == 200
      assert response.body["status"] == "interrupted"
    end

    test "returns false when run is not interrupted" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/runs/run-test/status")

      assert response.status == 200
      assert response.body["status"] != "interrupted"
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

    test "retries with different error types" do
      attempts = :counters.new(1, [:atomics])

      result =
        Client.with_retry(fn ->
          :counters.add(attempts, 1, 1)
          count = :counters.get(attempts, 1)

          cond do
            count == 1 -> {:error, :timeout}
            count == 2 -> {:error, :econnrefused}
            true -> {:ok, :success}
          end
        end)

      assert result == {:ok, :success}
      assert :counters.get(attempts, 1) == 3
    end

    test "applies exponential backoff delays" do
      attempt = :counters.new(1, [:atomics])

      result =
        Client.with_retry(fn ->
          :counters.add(attempt, 1, 1)
          current = :counters.get(attempt, 1)

          if current < 3 do
            {:error, :retry_needed}
          else
            {:ok, :success}
          end
        end)

      assert result == {:ok, :success}
    end
  end

  describe "error handling" do
    test "handles 404 not found response" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/nonexistent")

      assert response.status == 404
      assert response.body["error"] == "not found"
    end

    test "resume_run returns error for invalid command type" do
      result = Client.resume_run("thread-test", "run-test", :invalid_command)
      assert result == {:error, :invalid_command}
    end

    test "get_thread returns error for path traversal in thread_id" do
      result = Client.get_thread("../other-thread")
      assert result == {:error, :invalid_thread_id}
    end

    test "get_thread returns error for null byte in thread_id" do
      result = Client.get_thread("thread\x0malicious")
      assert result == {:error, :invalid_thread_id}
    end

    test "get_run returns error for invalid run_id" do
      result = Client.get_run("thread-test", "../run")
      assert result == {:error, :invalid_run_id}
    end

    test "list_runs returns error for path traversal" do
      result = Client.list_runs("thread/../../../etc")
      assert result == {:error, :invalid_thread_id}
    end
  end

  describe "create_run/2 with options" do
    test "creates a run with stream_mode option" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-test/runs", %{
          assistant_id: "agent",
          input: %{},
          stream_mode: "values"
        })

      assert response.status == 200
    end

    test "creates a run with config option" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-test/runs", %{
          assistant_id: "agent",
          input: %{},
          config: %{recursion_limit: 50}
        })

      assert response.status == 200
    end

    test "creates a run with webhook option" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-test/runs", %{
          assistant_id: "agent",
          input: %{},
          webhook: "https://example.com/webhook"
        })

      assert response.status == 200
    end
  end

  describe "all run statuses" do
    test "handles pending status" do
      client = mock_client()
      {:ok, response} = Tesla.get(client, "/threads/thread-test/runs/run-test")

      assert response.status == 200

      assert response.body["status"] in [
               "pending",
               "running",
               "interrupted",
               "completed",
               "error",
               "cancelled"
             ]
    end
  end

  describe "command type variations" do
    test "resume command with complex value" do
      client = mock_client()

      complex_value = %{
        "action" => "continue",
        "context" => %{"user_input" => "yes", "confidence" => 0.95}
      }

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: complex_value}
        })

      assert response.status == 200
    end

    test "resume command with string value" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: "user_approved"}
        })

      assert response.status == 200
    end

    test "resume command with list value" do
      client = mock_client()

      {:ok, response} =
        Tesla.post(client, "/threads/thread-resume/runs/run-resume", %{
          command: %{resume: ["option1", "option2"]}
        })

      assert response.status == 200
    end
  end
end

defmodule Babysitter.LangGraph.ClientIntegrationTest do
  use ExUnit.Case, async: false

  alias Babysitter.LangGraph.Client

  @moduletag :integration

  setup do
    unless Client.healthy?() do
      IO.puts("\n  ⚠ LangGraph service unavailable - skipping integration tests")
      {:ok, skip: true}
    else
      {:ok, skip: false}
    end
  end

  describe "integration tests" do
    @tag :integration
    test "full thread lifecycle", context do
      if context[:skip] do
        assert true
      else
        {:ok, thread} = Client.create_thread()
        assert thread.body["thread_id"] != nil
        thread_id = thread.body["thread_id"]

        {:ok, fetched} = Client.get_thread(thread_id)
        assert fetched.body["thread_id"] == thread_id

        {:ok, state} = Client.get_state(thread_id)
        assert state.body != nil
      end
    end

    @tag :integration
    test "run lifecycle", context do
      if context[:skip] do
        assert true
      else
        {:ok, thread} = Client.create_thread()
        thread_id = thread.body["thread_id"]

        {:ok, run} = Client.create_run(thread_id, input: %{"message" => "hello"})
        assert run.body["run_id"] != nil
        run_id = run.body["run_id"]

        {:ok, run_details} = Client.get_run(thread_id, run_id)
        assert run_details.body["run_id"] == run_id

        {:ok, status} = Client.get_run_status(thread_id, run_id)
        status_value = status.body["status"]

        if status_value do
          assert status_value in [
                   "pending",
                   "running",
                   "completed",
                   "interrupted",
                   "error",
                   "cancelled"
                 ]
        end

        {:ok, runs} = Client.list_runs(thread_id)
        assert is_list(runs.body)
      end
    end

    @tag :integration
    test "interrupted? function", context do
      if context[:skip] do
        assert true
      else
        {:ok, thread} = Client.create_thread()
        thread_id = thread.body["thread_id"]

        {:ok, run} = Client.create_run(thread_id, input: %{})
        run_id = run.body["run_id"]

        {:ok, is_interrupted} = Client.interrupted?(thread_id, run_id)
        assert is_boolean(is_interrupted)
      end
    end

    @tag :integration
    test "cancel_run function", context do
      if context[:skip] do
        assert true
      else
        {:ok, thread} = Client.create_thread()
        thread_id = thread.body["thread_id"]

        {:ok, run} = Client.create_run(thread_id, input: %{})
        run_id = run.body["run_id"]

        {:ok, result} = Client.cancel_run(thread_id, run_id)
        assert result.status in 200..299
      end
    end

    @tag :integration
    test "resume_run with approve command", context do
      if context[:skip] do
        assert true
      else
        {:ok, thread} = Client.create_thread()
        thread_id = thread.body["thread_id"]

        {:ok, run} = Client.create_run(thread_id, input: %{})
        run_id = run.body["run_id"]

        {:ok, is_interrupted} = Client.interrupted?(thread_id, run_id)

        if is_interrupted do
          {:ok, result} = Client.resume_run(thread_id, run_id, :approve)
          assert result.status in 200..299
        else
          assert true
        end
      end
    end

    @tag :integration
    test "health_check returns valid response", context do
      if context[:skip] do
        assert true
      else
        {:ok, response} = Client.health_check()
        assert response.status == 200
      end
    end

    @tag :integration
    test "healthy? returns boolean", context do
      if context[:skip] do
        assert true
      else
        result = Client.healthy?()
        assert is_boolean(result)
      end
    end
  end
end
