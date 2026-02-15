defmodule Babysitter.WorkflowLoader do
  @moduledoc """
  GenServer that loads workflow files at application startup.

  Watches for :reload message to re-load workflows.
  """

  use GenServer
  require Logger

  alias Babysitter.WorkflowStore
  alias Babysitter.Workflow.Parser

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, Keyword.put(opts, :name, __MODULE__))
  end

  @impl true
  def init(:ok) do
    Logger.info("Starting WorkflowLoader...")
    load_workflows()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    result = load_workflows()
    {:reply, result, state}
  end

  @impl true
  def handle_info(:reload, state) do
    load_workflows()
    {:noreply, state}
  end

  defp load_workflows do
    case Parser.load_all() do
      {:ok, workflows} when workflows != [] ->
        Enum.each(workflows, &WorkflowStore.put/1)
        Logger.info("Loaded #{length(workflows)} workflow(s) from .babysitter/workflows/")
        {:ok, length(workflows)}

      {:ok, []} ->
        Logger.info("No workflow files found in .babysitter/workflows/")
        :ok

      {:error, :enoent} ->
        Logger.info("Workflows directory .babysitter/workflows/ does not exist, skipping load")
        :ok

      {:error, reason} ->
        Logger.error("Failed to load workflows: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
