defmodule Babysitter.LangGraph.ConfigTest do
  use ExUnit.Case, async: true

  alias Babysitter.LangGraph.Config

  describe "base_url/0" do
    test "returns default base URL when not configured" do
      assert Config.base_url() == "http://127.0.0.1:8123"
    end

    test "returns configured base URL" do
      original = Application.get_env(:babysitter, :langgraph_base_url)
      Application.put_env(:babysitter, :langgraph_base_url, "http://custom:9000")

      assert Config.base_url() == "http://custom:9000"

      if original do
        Application.put_env(:babysitter, :langgraph_base_url, original)
      else
        Application.delete_env(:babysitter, :langgraph_base_url)
      end
    end
  end

  describe "timeout/0" do
    test "returns default timeout when not configured" do
      assert Config.timeout() == 30_000
    end
  end

  describe "max_retries/0" do
    test "returns default max retries when not configured" do
      assert Config.max_retries() == 3
    end
  end

  describe "base_delay_ms/0" do
    test "returns default base delay when not configured" do
      assert Config.base_delay_ms() == 1000
    end
  end
end
