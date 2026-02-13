defmodule BabysitterWeb.WorkflowControllerTest do
  use BabysitterWeb.ConnCase, async: false

  alias Babysitter.WorkflowStore

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
      WorkflowStore.put(%{id: "wf-4", name: "Test Workflow 4"})

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
end
