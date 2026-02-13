defmodule Babysitter.WorkflowStoreTest do
  use ExUnit.Case, async: false

  alias Babysitter.WorkflowStore

  setup do
    WorkflowStore.clear()
    :ok
  end

  describe "put/1 and get/1" do
    test "stores and retrieves a workflow" do
      workflow = %{id: "wf-1", name: "Test Workflow"}
      assert :ok = WorkflowStore.put(workflow)
      assert {:ok, ^workflow} = WorkflowStore.get("wf-1")
    end

    test "returns error for nonexistent workflow" do
      assert {:error, :not_found} = WorkflowStore.get("nonexistent")
    end
  end

  describe "list/0" do
    test "lists all workflows" do
      WorkflowStore.put(%{id: "wf-2", name: "Workflow 2"})
      WorkflowStore.put(%{id: "wf-3", name: "Workflow 3"})

      workflows = WorkflowStore.list()
      ids = Enum.map(workflows, & &1.id)
      assert "wf-2" in ids
      assert "wf-3" in ids
    end
  end

  describe "delete/1" do
    test "deletes a workflow" do
      WorkflowStore.put(%{id: "wf-4", name: "Workflow 4"})
      assert :ok = WorkflowStore.delete("wf-4")
      assert {:error, :not_found} = WorkflowStore.get("wf-4")
    end
  end

  describe "clear/0" do
    test "clears all workflows" do
      WorkflowStore.put(%{id: "wf-5", name: "Workflow 5"})
      WorkflowStore.put(%{id: "wf-6", name: "Workflow 6"})

      assert :ok = WorkflowStore.clear()
      assert WorkflowStore.list() == []
    end
  end
end
