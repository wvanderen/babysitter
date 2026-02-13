defmodule Babysitter.WorkflowStore do
  @moduledoc """
  In-memory store for workflow definitions.
  """

  use Agent

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  def put(workflow) do
    Agent.update(__MODULE__, &Map.put(&1, workflow.id, workflow))
    :ok
  end

  def get(id) do
    case Agent.get(__MODULE__, &Map.get(&1, id)) do
      nil -> {:error, :not_found}
      workflow -> {:ok, workflow}
    end
  end

  def list do
    Agent.get(__MODULE__, &Map.values/1)
  end

  def delete(id) do
    Agent.update(__MODULE__, &Map.delete(&1, id))
    :ok
  end

  def clear do
    Agent.update(__MODULE__, fn _ -> %{} end)
    :ok
  end
end
