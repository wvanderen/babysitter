defmodule Babysitter.E2E.WorkflowTest do
  use ExUnit.Case, async: false

  alias Babysitter.{Workflow.Parser, WorkflowInstance, WorkflowStore, SessionManager}

  @three_stage_workflow """
  id: e2e-three-stage
  name: Three Stage Test Workflow
  description: E2E test workflow with 3 stages
  stages:
    - id: setup
      type: action
      name: Setup Stage
      command: echo "Setting up..."
      on_success: build
    - id: build
      type: action
      name: Build Stage
      command: echo "Building..."
      on_success: verify
    - id: verify
      type: action
      name: Verify Stage
      command: echo "Verifying..."
  """

  setup_all do
    {:ok, workflow} = Parser.parse_string(@three_stage_workflow)
    WorkflowStore.put(workflow)
    :ok
  end

  setup do
    SessionManager.clear()

    on_exit(fn ->
      SessionManager.clear()
    end)

    :ok
  end

  defp unique_session_id do
    "e2e-#{:rand.uniform(1_000_000)}"
  end

  defp create_session do
    id = unique_session_id()
    {:ok, _session} = SessionManager.create_session(id)
    id
  end

  defp start_workflow_instance(session_id) do
    instance_id = "inst-#{:rand.uniform(1_000_000)}"

    spec = {
      WorkflowInstance,
      id: instance_id, workflow_id: "e2e-three-stage", session_id: session_id
    }

    {:ok, pid} = start_supervised(spec)
    {instance_id, pid}
  end

  describe "3-stage workflow execution" do
    @moduletag :e2e

    test "executes stages in sequence" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      assert {:ok, _} = WorkflowInstance.start(instance_id)
      assert {:ok, :running} = WorkflowInstance.get_status(instance_id)

      {:ok, state} = WorkflowInstance.get_state(instance_id)
      assert state.current_stage != nil
    end

    test "tracks stage execution timing" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      {:ok, _} = WorkflowInstance.start(instance_id)

      {:ok, state} = WorkflowInstance.get_state(instance_id)
      assert state.started_at != nil
    end

    test "preserves stage order from workflow definition" do
      {:ok, workflow} = WorkflowStore.get("e2e-three-stage")

      assert workflow.stage_order == [:setup, :build, :verify]
    end

    test "supports pause and resume during execution" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      {:ok, _} = WorkflowInstance.start(instance_id)
      assert {:ok, :paused} = WorkflowInstance.pause(instance_id)
      assert {:ok, :paused} = WorkflowInstance.get_status(instance_id)

      assert {:ok, :running} = WorkflowInstance.resume(instance_id)
      assert {:ok, :running} = WorkflowInstance.get_status(instance_id)
    end

    test "completes workflow successfully" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      {:ok, _} = WorkflowInstance.start(instance_id)

      assert {:ok, :completed} = WorkflowInstance.complete(instance_id)

      {:ok, state} = WorkflowInstance.get_state(instance_id)
      assert state.status == :completed
      assert state.completed_at != nil
    end
  end

  describe "variable interpolation in workflow" do
    @moduletag :e2e

    test "sets and retrieves workflow variables" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      WorkflowInstance.set_variable(instance_id, "test_var", "test_value")
      {:ok, state} = WorkflowInstance.get_state(instance_id)

      assert state.variables["test_var"] == "test_value"
    end

    test "sets multiple variables at once" do
      session_id = create_session()
      {instance_id, _pid} = start_workflow_instance(session_id)

      WorkflowInstance.set_variables(instance_id, %{
        "issue_id" => "td-123",
        "branch" => "feature/test"
      })

      {:ok, state} = WorkflowInstance.get_state(instance_id)
      assert state.variables["issue_id"] == "td-123"
      assert state.variables["branch"] == "feature/test"
    end
  end
end
