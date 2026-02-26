defmodule BabysitterWeb.WorkflowControllerTest do
  use BabysitterWeb.ConnCase, async: false

  alias Babysitter.{WorkflowStore, WorkflowSupervisor, SessionManager}

  setup do
    WorkflowStore.clear()
    :ok
  end

  describe "GET /api/workflows" do
    test "lists all workflows" do
      WorkflowStore.put(%{id: "wf-1", name: "Test Workflow"})

      conn = get(build_conn(), "/api/workflows")
      response = json_response(conn, 200)

      assert length(response["workflows"]) == 1
      assert hd(response["workflows"])["id"] == "wf-1"
    end
  end

  describe "GET /api/workflows/:id" do
    test "shows a workflow" do
      WorkflowStore.put(%{id: "wf-2", name: "Test Workflow 2"})

      conn = get(build_conn(), "/api/workflows/wf-2")
      response = json_response(conn, 200)

      assert response["workflow"]["id"] == "wf-2"
    end

    test "returns 404 for nonexistent workflow" do
      conn = get(build_conn(), "/api/workflows/nonexistent")
      assert conn.status == 404
    end
  end

  describe "POST /api/workflows" do
    test "creates a workflow" do
      conn =
        post(build_conn(), "/api/workflows", %{
          workflow: %{
            id: "wf-3",
            name: "New Workflow",
            stages: []
          }
        })

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["workflow"]["id"] == "wf-3"
      assert response["workflow"]["name"] == "New Workflow"
    end
  end

  describe "POST /api/workflows/:id/execute" do
    test "starts workflow execution" do
      workflow = %{
        id: "wf-4",
        name: "Test Workflow 4",
        stages: %{
          stage1: %{type: :action, command: "echo test"}
        },
        stage_order: [:stage1],
        entry_point: :stage1
      }

      WorkflowStore.put(workflow)

      conn = post(build_conn(), "/api/workflows/wf-4/execute")
      response = json_response(conn, 200)

      assert response["workflow_id"] == "wf-4"
      assert response["status"] == "started"
    end

    test "returns 404 for nonexistent workflow" do
      conn = post(build_conn(), "/api/workflows/nonexistent/execute")
      assert conn.status == 404
    end
  end

  describe "GET /api/workflows/:workflow_id/instances/:instance_id" do
    setup do
      workflow = %{
        id: "wf-instance-test",
        name: "Instance Test Workflow",
        stages: %{
          stage1: %{type: :action, command: "echo test"}
        },
        stage_order: [:stage1],
        entry_point: :stage1
      }

      WorkflowStore.put(workflow)
      {:ok, session} = SessionManager.create_session("sess-instance-test")

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("wf-instance-test",
          session_id: "sess-instance-test",
          auto_start: false
        )

      on_exit(fn ->
        WorkflowSupervisor.stop_workflow(instance_id)
        SessionManager.destroy_session("sess-instance-test")
      end)

      {:ok, instance_id: instance_id}
    end

    test "returns instance details", %{instance_id: instance_id} do
      conn = get(build_conn(), "/api/workflows/wf-instance-test/instances/#{instance_id}")
      response = json_response(conn, 200)

      assert response["instance"]["id"] == instance_id
      assert response["instance"]["workflow_id"] == "wf-instance-test"
      assert response["instance"]["session_id"] == "sess-instance-test"
      assert response["instance"]["status"] == "pending"
      assert response["instance"]["current_stage"] == nil
      assert response["instance"]["execution_history"] == []
    end

    test "returns 404 for nonexistent workflow" do
      conn = get(build_conn(), "/api/workflows/nonexistent/instances/some-instance")
      assert conn.status == 404
    end

    test "returns 404 for nonexistent instance" do
      conn = get(build_conn(), "/api/workflows/wf-instance-test/instances/nonexistent")
      assert conn.status == 404
    end
  end

  describe "GET /api/workflows/:workflow_id/instances/:instance_id/history" do
    setup do
      workflow = %{
        id: "wf-history-test",
        name: "History Test Workflow",
        stages: %{
          stage1: %{type: :action, command: "echo test"}
        },
        stage_order: [:stage1],
        entry_point: :stage1
      }

      WorkflowStore.put(workflow)
      {:ok, session} = SessionManager.create_session("sess-history-test")

      {:ok, instance_id} =
        WorkflowSupervisor.start_workflow("wf-history-test",
          session_id: "sess-history-test",
          auto_start: false
        )

      on_exit(fn ->
        WorkflowSupervisor.stop_workflow(instance_id)
        SessionManager.destroy_session("sess-history-test")
      end)

      {:ok, instance_id: instance_id}
    end

    test "returns execution history", %{instance_id: instance_id} do
      conn = get(build_conn(), "/api/workflows/wf-history-test/instances/#{instance_id}/history")
      response = json_response(conn, 200)

      assert response["history"] == []
    end

    test "returns 404 for nonexistent workflow" do
      conn = get(build_conn(), "/api/workflows/nonexistent/instances/some-instance/history")
      assert conn.status == 404
    end

    test "returns 404 for nonexistent instance" do
      conn = get(build_conn(), "/api/workflows/wf-history-test/instances/nonexistent/history")
      assert conn.status == 404
    end
  end
end
