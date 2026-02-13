defmodule BabysitterWeb.SessionControllerTest do
  use BabysitterWeb.ConnCase, async: false

  alias Babysitter.SessionManager

  setup do
    SessionManager.clear()
    :ok
  end

  describe "GET /api/sessions" do
    test "lists all sessions" do
      {:ok, _} = SessionManager.create_session("test-1")
      {:ok, _} = SessionManager.create_session("test-2")

      conn = get(build_conn(), "/api/sessions")
      response = json_response(conn, 200)

      assert length(response["sessions"]) == 2
      ids = Enum.map(response["sessions"], & &1["id"])
      assert "test-1" in ids
      assert "test-2" in ids
    end
  end

  describe "GET /api/sessions/:id" do
    test "shows a session" do
      {:ok, _} = SessionManager.create_session("test-3")

      conn = get(build_conn(), "/api/sessions/test-3")
      response = json_response(conn, 200)

      assert response["session"]["id"] == "test-3"
    end

    test "returns 404 for nonexistent session" do
      conn = get(build_conn(), "/api/sessions/nonexistent")
      assert conn.status == 404
    end
  end

  describe "POST /api/sessions" do
    test "creates a session" do
      conn =
        post(build_conn(), "/api/sessions", %{
          session: %{"id" => "test-4"}
        })

      assert conn.status == 201
      response = json_response(conn, 201)
      assert response["session"]["id"] == "test-4"
    end

    test "generates id if not provided" do
      conn = post(build_conn(), "/api/sessions", %{session: %{}})
      response = json_response(conn, 201)
      assert response["session"]["id"] != nil
    end
  end

  describe "DELETE /api/sessions/:id" do
    test "deletes a session" do
      {:ok, _} = SessionManager.create_session("test-5")

      conn = delete(build_conn(), "/api/sessions/test-5")
      response = json_response(conn, 200)

      assert response["session"]["status"] == "stopped"
    end

    test "returns 404 for nonexistent session" do
      conn = delete(build_conn(), "/api/sessions/nonexistent")
      assert conn.status == 404
    end
  end
end
