defmodule Babysitter.LangGraph.Config do
  @moduledoc """
  Configuration for LangGraph service connection.

  Reads from application environment or provides sensible defaults.
  """

  @default_base_url "http://127.0.0.1:8123"
  @default_timeout 30_000
  @default_max_retries 3
  @default_base_delay_ms 1000

  @doc """
  Get the base URL for the LangGraph service.
  """
  @spec base_url() :: String.t()
  def base_url do
    Application.get_env(:babysitter, :langgraph_base_url, @default_base_url)
  end

  @doc """
  Get the request timeout in milliseconds.
  """
  @spec timeout() :: non_neg_integer()
  def timeout do
    Application.get_env(:babysitter, :langgraph_timeout, @default_timeout)
  end

  @doc """
  Get the maximum number of retries for failed requests.
  """
  @spec max_retries() :: non_neg_integer()
  def max_retries do
    Application.get_env(:babysitter, :langgraph_max_retries, @default_max_retries)
  end

  @doc """
  Get the base delay in milliseconds for exponential backoff.
  """
  @spec base_delay_ms() :: non_neg_integer()
  def base_delay_ms do
    Application.get_env(:babysitter, :langgraph_base_delay_ms, @default_base_delay_ms)
  end
end
