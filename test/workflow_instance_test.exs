defmodule Babysitter.WorkflowInstanceTest do
  use ExUnit.Case, async: false

  alias Babysitter.{
    WorkflowInstance,
    WorkflowStore,
    Workflow.Parser,
    SessionManager,
    Intervention
  }

  setup_all do
    workflow_yaml = """
    id: instance-test-workflow
    name: Instance Test Workflow
    stages:
      - id: start
        type: action
        command: echo "starting"
        on_success: middle
      - id: middle
        type: action
        command: echo "middle"
        on_success: end
        on_failure: retry
      - id: retry
        type: decision
        on_success: middle
      - id: end
        type: action
        command: echo "done"
    """

    {:ok, workflow} = Parser.parse_string(workflow_yaml)
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

  defp create_session do
    id = "sess-#{:rand.uniform(1_000_000)}"
    {:ok, session} = SessionManager.create_session(id)
    session.id
  end

  defp start_instance(opts \\ []) do
    session_id = Keyword.get(opts, :session_id, create_session())
    id = Keyword.get(opts, :id, "inst-#{:rand.uniform(1_000_000)}")
    max_retries = Keyword.get(opts, :max_retries, 3)

    spec =
      {WorkflowInstance,
       id: id,
       workflow_id: "instance-test-workflow",
       session_id: session_id,
       max_retries: max_retries}

    {:ok, pid} = start_supervised(spec)
    {id, pid}
  end

  describe "start_link/1" do
    test "starts a workflow instance process" do
      {id, pid} = start_instance()
      assert Process.alive?(pid)
      assert WorkflowInstance.whereis(id) == pid
    end

    test "initializes with pending status" do
      {id, _pid} = start_instance()
      assert {:ok, :pending} = WorkflowInstance.get_status(id)
    end
  end

  describe "via_tuple/1 and whereis/1" do
    test "lookup returns pid for registered instance" do
      {id, _pid} = start_instance()
      assert is_pid(WorkflowInstance.whereis(id))
    end

    test "lookup returns nil for unregistered instance" do
      assert WorkflowInstance.whereis("nonexistent") == nil
    end
  end

  describe "start/2" do
    test "transitions to running status" do
      {id, _pid} = start_instance()
      assert {:ok, _} = WorkflowInstance.start(id)
      assert {:ok, :running} = WorkflowInstance.get_status(id)
    end

    test "sets started_at timestamp" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.started_at != nil
    end

    test "sets current stage to entry point" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.current_stage != nil
    end

    test "returns error for invalid transition" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      assert {:error, {:invalid_transition, :running, :running}} = WorkflowInstance.start(id)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses a running instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      assert {:ok, :paused} = WorkflowInstance.pause(id)
      assert {:ok, :paused} = WorkflowInstance.get_status(id)
    end

    test "resumes a paused instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, :paused} = WorkflowInstance.pause(id)
      assert {:ok, :running} = WorkflowInstance.resume(id)
    end

    test "cannot pause from pending" do
      {id, _pid} = start_instance()
      assert {:error, {:invalid_transition, :pending, :paused}} = WorkflowInstance.pause(id)
    end
  end

  describe "stop/1" do
    test "stops an instance" do
      {id, _pid} = start_instance()
      assert :ok = WorkflowInstance.stop(id)
      assert {:ok, :stopped} = WorkflowInstance.get_status(id)
    end
  end

  describe "complete/1" do
    test "completes a running instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      assert {:ok, :completed} = WorkflowInstance.complete(id)
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.completed_at != nil
    end
  end

  describe "fail/2" do
    test "fails a running instance with reason" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      assert {:ok, :failed} = WorkflowInstance.fail(id, "Test failure")
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.failure_reason == "Test failure"
    end
  end

  describe "escalate/2" do
    test "escalates a running instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      assert {:ok, :escalated} = WorkflowInstance.escalate(id, "Human needed")
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.escalation_reason == "Human needed"
    end

    test "escalates a paused instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, :paused} = WorkflowInstance.pause(id)
      assert {:ok, :escalated} = WorkflowInstance.escalate(id, "Escalated while paused")
    end
  end

  describe "retry/1" do
    test "retries a failed instance" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, :failed} = WorkflowInstance.fail(id, "Failed")
      assert {:ok, :retrying} = WorkflowInstance.retry(id)
      assert {:ok, :running} = WorkflowInstance.get_status(id)
    end

    test "returns error when max retries exceeded" do
      {id, _pid} = start_instance(max_retries: 0)
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, :failed} = WorkflowInstance.fail(id, "Failed")
      assert {:error, :max_retries_exceeded} = WorkflowInstance.retry(id)
    end

    test "clears failure reason on retry" do
      {id, _pid} = start_instance()
      {:ok, _} = WorkflowInstance.start(id)
      {:ok, :failed} = WorkflowInstance.fail(id, "Failed")
      {:ok, :retrying} = WorkflowInstance.retry(id)
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.failure_reason == nil
    end
  end

  describe "set_variable/3 and set_variables/2" do
    test "sets a single variable" do
      {id, _pid} = start_instance()
      WorkflowInstance.set_variable(id, "issue_id", "td-123")
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.variables["issue_id"] == "td-123"
    end

    test "sets multiple variables" do
      {id, _pid} = start_instance()
      WorkflowInstance.set_variables(id, %{"a" => 1, "b" => 2})
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.variables["a"] == 1
      assert state.variables["b"] == 2
    end
  end

  describe "get_history/1" do
    test "returns empty history initially" do
      {id, _pid} = start_instance()
      assert {:ok, []} = WorkflowInstance.get_history(id)
    end
  end

  describe "state transitions" do
    test "valid_transitions for pending" do
      {id, _pid} = start_instance()
      {:ok, state} = WorkflowInstance.get_state(id)
      assert state.status == :pending
    end
  end

  describe "intervention integration" do
    setup do
      workflow_yaml = """
      id: intervention-test-workflow
      name: Intervention Test Workflow
      stages:
        - id: fail_stage
          type: action
          command: exit 1
      """

      {:ok, workflow} = Parser.parse_string(workflow_yaml)
      WorkflowStore.put(workflow)
      :ok
    end

    test "intervention triggers retry on validation failure" do
      session_context = %{
        current_stage: :fail_stage,
        status: :running,
        retries: %{fail_stage: 0},
        max_retries: 3,
        validations: [%{status: :fail, type: :test, output: "err", exit_code: 1}]
      }

      result = Intervention.check(session_context, :dumb)

      assert result.action == :retry
      assert result.reason =~ "Validation"
    end

    test "intervention escalates when max retries exceeded" do
      session_context = %{
        current_stage: :fail_stage,
        status: :running,
        retries: %{fail_stage: 3},
        max_retries: 3
      }

      result = Intervention.check(session_context, :dumb)

      assert result.action == :escalate
      assert result.reason =~ "Max retries"
    end

    test "intervention restarts on timeout" do
      session_context = %{
        current_stage: :fail_stage,
        status: :timeout,
        retries: %{fail_stage: 0},
        max_retries: 3
      }

      result = Intervention.check(session_context, :dumb)

      assert result.action == :restart
      assert result.reason =~ "timed out"
    end

    test "intervention escalates when stuck too long" do
      stuck_time = DateTime.utc_now() |> DateTime.add(-15, :minute)

      session_context = %{
        current_stage: :fail_stage,
        status: :running,
        retries: %{fail_stage: 0},
        last_activity: stuck_time,
        stuck_threshold_minutes: 10
      }

      result = Intervention.check(session_context, :dumb)

      assert result.action == :escalate
      assert result.reason =~ "No progress"
    end
  end
end
