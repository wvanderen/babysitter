defmodule BabysitterWeb.HealthControllerTest do
  use BabysitterWeb.ConnCase, async: false

  describe "GET /api/health" do
    test "returns ok status" do
      conn = get(build_conn(), "/api/health")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
    end
  end

  describe "GET /api/ready" do
    test "returns ready when WorkflowStore is running" do
      conn = get(build_conn(), "/api/ready")
      response = json_response(conn, 200)

      assert response["status"] == "ready"
    end
  end

  describe "GET /api/status" do
    test "returns status with workflow count and uptime" do
      conn = get(build_conn(), "/api/status")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
      assert is_integer(response["workflow_count"])
      assert is_integer(response["uptime_seconds"])
    end
  end
end
