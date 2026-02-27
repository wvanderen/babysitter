defmodule Babysitter.LangGraph.IntegrationTest do
  use ExUnit.Case, async: false

  alias Babysitter.LangGraph.Client

  @moduletag :integration

  setup do
    if service_available?() do
      :ok
    else
      {:skip, "LangGraph service not available at http://127.0.0.1:8123"}
    end
  end

  describe "Client integration with LangGraph service" do
    @tag :integration
    test "health_check/0 returns ok when service is running" do
      assert {:ok, %Tesla.Env{status: 200}} = Client.health_check()
    end

    @tag :integration
    test "create_thread/0 creates a thread" do
      assert {:ok, %Tesla.Env{status: 200, body: body}} = Client.create_thread()
      assert Map.has_key?(body, "thread_id")
    end

    @tag :integration
    test "get_thread/1 retrieves a thread" do
      {:ok, %Tesla.Env{body: %{"thread_id" => thread_id}}} = Client.create_thread()
      assert {:ok, %Tesla.Env{status: 200}} = Client.get_thread(thread_id)
    end

    @tag :integration
    test "create_run/2 starts a run" do
      {:ok, %Tesla.Env{body: %{"thread_id" => thread_id}}} = Client.create_thread()

      assert {:ok, %Tesla.Env{status: 200, body: body}} =
               Client.create_run(thread_id, assistant_id: "agent", input: %{})

      assert Map.has_key?(body, "run_id")
    end

    @tag :integration
    test "get_state/1 retrieves thread state" do
      {:ok, %Tesla.Env{body: %{"thread_id" => thread_id}}} = Client.create_thread()
      assert {:ok, %Tesla.Env{status: 200}} = Client.get_state(thread_id)
    end

    @tag :integration
    test "healthy?/0 returns true when service is running" do
      assert Client.healthy?() == true
    end
  end

  defp service_available? do
    case Client.health_check() do
      {:ok, %Tesla.Env{status: 200}} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
