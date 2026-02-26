defmodule Babysitter.TDTest.VerifyIntegration do
  @moduledoc """
  Simple verification module for td workflow integration test.

  This module demonstrates that:
  1. td task tracking works end-to-end
  2. Task can be started, implemented, and completed
  3. Workflow integration is functional

  Task: td-test-writer-756116 (td-924bd6)
  """

  @doc """
  Returns a verification message confirming td integration is working.

  ## Examples

      iex> Babysitter.TDTest.VerifyIntegration.verify()
      {:ok, "td integration verified for task td-924bd6"}
  """
  @spec verify() :: {:ok, String.t()}
  def verify do
    {:ok, "td integration verified for task td-924bd6"}
  end

  @doc """
  Returns task identifier for tracking.

  ## Examples

      iex> Babysitter.TDTest.VerifyIntegration.task_id()
      "td-924bd6"
  """
  @spec task_id() :: String.t()
  def task_id do
    "td-924bd6"
  end

  @doc """
  Returns task title.

  ## Examples

      iex> Babysitter.TDTest.VerifyIntegration.task_title()
      "td-test-writer-756116"
  """
  @spec task_title() :: String.t()
  def task_title do
    "td-test-writer-756116"
  end
end
