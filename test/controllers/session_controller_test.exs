defmodule BabysitterWeb.SessionControllerTest do
  use BabysitterWeb.ConnCase, async: false

  alias Babysitter.SessionManager

  setup do
    SessionManager.clear()
    :ok
  end

  defp unique_id(prefix) do
    "#{prefix}-#{:rand.uniform(1_000_000)}"
  end

  describe "GET /api/sessions" do
    test "lists all sessions" do
      id1 = unique_id("test")
      id2 = unique_id("test")
      {:ok, _} = SessionManager.create_session(id1)
      {:ok, _} = SessionManager.create_session(id2)

      conn = get(build_conn(), "/api/sessions")
      response = json_response(conn, 200)

      assert length(response["sessions"]) == 2
      ids = Enum.map(response["sessions"], & &1["id"])
      assert id1 in ids
      assert id2 in ids
    end
  end

  describe "GET /api/sessions/:id" do
    test "shows a session" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn = get(build_conn(), "/api/sessions/#{id}")
      response = json_response(conn, 200)

      assert response["session"]["id"] == id
    end

    test "returns 404 for nonexistent session" do
      conn = get(build_conn(), "/api/sessions/nonexistent")
      assert conn.status == 404
    end
  end

  describe "POST /api/sessions" do
    test "creates a session" do
      id = unique_id("test")

      conn =
        post(build_conn(), "/api/sessions", %{
          session: %{"id" => id}
        })

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["session"]["id"] == id
    end

    test "generates id if not provided" do
      conn = post(build_conn(), "/api/sessions", %{session: %{}})
      response = json_response(conn, 201)
      assert response["session"]["id"] != nil
    end
  end

  describe "DELETE /api/sessions/:id" do
    test "deletes a session" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn = delete(build_conn(), "/api/sessions/#{id}")
      response = json_response(conn, 200)

      assert response["status"] == "deleted"
    end

    test "returns 404 for nonexistent session" do
      conn = delete(build_conn(), "/api/sessions/nonexistent")
      assert conn.status == 404
    end
  end

  describe "POST /api/sessions/:id/intervene" do
    test "performs retry action" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)
      {:ok, _} = Babysitter.Session.pause(id)

      conn =
        post(build_conn(), "/api/sessions/#{id}/intervene", %{
          action: "retry",
          reason: "Manual retry"
        })

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["action"] == "retry"
    end

    test "performs escalate action" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn =
        post(build_conn(), "/api/sessions/#{id}/intervene", %{
          action: "escalate",
          reason: "Manual escalation"
        })

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["action"] == "escalate"
    end

    test "performs skip action" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn =
        post(build_conn(), "/api/sessions/#{id}/intervene", %{
          action: "skip",
          reason: "Skip this stage"
        })

      response = json_response(conn, 200)
      assert response["status"] == "ok"
      assert response["action"] == "skip"
    end

    test "returns 404 for nonexistent session" do
      conn =
        post(build_conn(), "/api/sessions/nonexistent/intervene", %{
          action: "retry"
        })

      assert conn.status == 404
    end

    test "returns 400 for missing action" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn = post(build_conn(), "/api/sessions/#{id}/intervene", %{})

      assert conn.status == 400
    end

    test "returns 400 for unknown action" do
      id = unique_id("test")
      {:ok, _} = SessionManager.create_session(id)

      conn =
        post(build_conn(), "/api/sessions/#{id}/intervene", %{
          action: "invalid_action"
        })

      assert conn.status == 400
    end
  end
end
