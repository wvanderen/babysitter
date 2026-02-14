defmodule Babysitter.WorkflowSupervisorTest do
  use ExUnit.Case, async: false

  alias Babysitter.{WorkflowSupervisor, WorkflowStore, Workflow.Parser, SessionManager}

  setup_all do
    yaml = """
    id: test-workflow
    name: Test Workflow
    stages:
      - id: first
        type: action
        command: echo "first"
        on_success: second
      - id: second
        type: action
        command: echo "second"
    """

    {:ok, workflow} = Parser.parse_string(yaml)
    WorkflowStore.put(workflow)
    :ok
  end

  setup do
    SessionManager.clear()

    on_exit(fn ->
      WorkflowSupervisor.stop_all()
      SessionManager.clear()
    end)

    :ok
  end

  defp create_session do
    id = "session-#{:rand.uniform(1_000_000)}"
    {:ok, session} = SessionManager.create_session(id)
    session.id
  end

  describe "start_workflow/2" do
    test "creates and starts a workflow instance" do
      session_id = create_session()

      assert {:ok, instance_id} =
               WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      assert String.starts_with?(instance_id, "wf-")
    end

    test "requires session_id" do
      assert {:ok, _} = WorkflowSupervisor.start_workflow("test-workflow", session_id: nil)
    end

    test "returns error for non-existent workflow" do
      session_id = create_session()

      assert {:error, _} =
               WorkflowSupervisor.start_workflow("nonexistent", session_id: session_id)
    end

    test "accepts variables option" do
      session_id = create_session()

      assert {:ok, _} =
               WorkflowSupervisor.start_workflow("test-workflow",
                 session_id: session_id,
                 variables: %{"issue_id" => "td-123"}
               )
    end
  end

  describe "create_workflow/2" do
    test "creates instance without starting" do
      session_id = create_session()

      assert {:ok, instance_id} =
               WorkflowSupervisor.create_workflow("test-workflow", session_id: session_id)

      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.status == :pending
    end
  end

  describe "run_workflow/2" do
    test "starts a created workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.create_workflow("test-workflow", session_id: session_id)

      assert {:ok, _} = WorkflowSupervisor.run_workflow(instance_id)
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = WorkflowSupervisor.run_workflow("nonexistent")
    end
  end

  describe "get_state/1" do
    test "returns instance state" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.id == instance_id
      assert state.workflow_id == "test-workflow"
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = WorkflowSupervisor.get_state("nonexistent")
    end
  end

  describe "get_status/1" do
    test "returns instance status" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert {:ok, :pending} = WorkflowSupervisor.get_status(instance_id)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses a running workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      assert {:ok, :paused} = WorkflowSupervisor.pause(instance_id)
      assert {:ok, :paused} = WorkflowSupervisor.get_status(instance_id)
    end

    test "resumes a paused workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      {:ok, :paused} = WorkflowSupervisor.pause(instance_id)
      assert {:ok, :running} = WorkflowSupervisor.resume(instance_id)
    end

    test "returns error for invalid pause" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.create_workflow("test-workflow", session_id: session_id)

      assert {:error, {:invalid_transition, :pending, :paused}} =
               WorkflowSupervisor.pause(instance_id)
    end
  end

  describe "stop_workflow/1" do
    test "stops and removes workflow instance" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert :ok = WorkflowSupervisor.stop_workflow(instance_id)
      assert {:error, :not_found} = WorkflowSupervisor.get_state(instance_id)
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = WorkflowSupervisor.stop_workflow("nonexistent")
    end
  end

  describe "set_variable/3 and set_variables/2" do
    test "sets a single variable" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert :ok = WorkflowSupervisor.set_variable(instance_id, "issue_id", "td-123")

      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.variables["issue_id"] == "td-123"
    end

    test "sets multiple variables" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert :ok =
               WorkflowSupervisor.set_variables(instance_id, %{
                 "issue_id" => "td-123",
                 "branch" => "main"
               })

      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.variables["issue_id"] == "td-123"
      assert state.variables["branch"] == "main"
    end
  end

  describe "fail/2" do
    test "fails a running workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      assert {:ok, :failed} = WorkflowSupervisor.fail(instance_id, "Something went wrong")
      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.failure_reason == "Something went wrong"
    end
  end

  describe "escalate/2" do
    test "escalates a running workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      assert {:ok, :escalated} = WorkflowSupervisor.escalate(instance_id, "Needs human review")
      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.escalation_reason == "Needs human review"
    end
  end

  describe "retry/1" do
    test "retries a failed workflow" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow", session_id: session_id)

      {:ok, :failed} = WorkflowSupervisor.fail(instance_id, "Test failure")
      assert {:ok, :retrying} = WorkflowSupervisor.retry(instance_id)
      {:ok, state} = WorkflowSupervisor.get_state(instance_id)
      assert state.retry_count == 1
    end
  end

  describe "list_workflows/0" do
    test "lists all active workflows" do
      session_id = create_session()

      {:ok, id1} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      {:ok, id2} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      workflows = WorkflowSupervisor.list_workflows()
      ids = Enum.map(workflows, fn {id, _, _} -> id end)
      assert id1 in ids
      assert id2 in ids
    end
  end

  describe "count_workflows/0" do
    test "counts active workflows" do
      session_id = create_session()

      initial_count = WorkflowSupervisor.count_workflows()

      {:ok, _} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert WorkflowSupervisor.count_workflows() == initial_count + 1
    end
  end

  describe "exists?/1" do
    test "returns true for existing instance" do
      session_id = create_session()

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      assert WorkflowSupervisor.exists?(instance_id)
    end

    test "returns false for non-existing instance" do
      refute WorkflowSupervisor.exists?("nonexistent")
    end
  end

  describe "stop_all/0" do
    test "stops all workflow instances" do
      session_id = create_session()

      {:ok, _} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      {:ok, _} =
        WorkflowSupervisor.start_workflow("test-workflow",
          session_id: session_id,
          auto_start: false
        )

      :ok = WorkflowSupervisor.stop_all()
      assert WorkflowSupervisor.count_workflows() == 0
    end
  end
end
