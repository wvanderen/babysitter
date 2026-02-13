defmodule Babysitter.SessionTest do
  use ExUnit.Case, async: false

  alias Babysitter.Session

  setup do
    session_id = "test-session-#{:rand.uniform(1_000_000)}"
    {:ok, session_id: session_id}
  end

  describe "start_link/1" do
    test "creates session with tmux integration", %{session_id: id} do
      assert {:ok, pid} = start_session(id)
      assert is_pid(pid)

      {:ok, state} = Session.get_state(id)
      assert state.id == id
      assert state.status == :running
      assert state.tmux_name == "babysitter-#{id}"

      stop_session(id)
    end

    test "accepts custom tmux name", %{session_id: id} do
      custom_name = "custom-tmux-#{:rand.uniform(1_000_000)}"
      assert {:ok, _pid} = start_session(id, tmux_name: custom_name)

      {:ok, state} = Session.get_state(id)
      assert state.tmux_name == custom_name

      stop_session(id)
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses and resumes session", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      assert {:ok, :paused} = Session.pause(id)
      {:ok, status} = Session.get_status(id)
      assert status == :paused

      assert {:ok, :running} = Session.resume(id)
      {:ok, status} = Session.get_status(id)
      assert status == :running

      stop_session(id)
    end

    test "returns error when pausing already paused session", %{session_id: id} do
      {:ok, _pid} = start_session(id)
      {:ok, :paused} = Session.pause(id)

      assert {:error, :already_paused} = Session.pause(id)

      stop_session(id)
    end

    test "returns error when resuming running session", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      assert {:error, :not_paused} = Session.resume(id)

      stop_session(id)
    end
  end

  describe "output buffer" do
    test "starts with empty buffer", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      {:ok, output} = Session.get_output(id)
      assert output == ""

      stop_session(id)
    end

    test "appends output to buffer", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      Session.append_output(id, "First line\n")
      Session.append_output(id, "Second line\n")

      {:ok, output} = Session.get_output(id)
      assert output == "First line\nSecond line\n"

      stop_session(id)
    end

    test "clears buffer", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      Session.append_output(id, "Some output")
      {:ok, output} = Session.get_output(id)
      refute output == ""

      :ok = Session.clear_buffer(id)
      {:ok, output} = Session.get_output(id)
      assert output == ""

      stop_session(id)
    end

    test "truncates buffer when exceeding max size", %{session_id: id} do
      {:ok, _pid} = start_session(id, max_buffer_size: 50)

      long_output = String.duplicate("x", 60)
      Session.append_output(id, long_output)

      {:ok, output} = Session.get_output(id)
      assert byte_size(output) == 50

      stop_session(id)
    end
  end

  describe "stop/1" do
    test "stops session and cleans up tmux", %{session_id: id} do
      {:ok, _pid} = start_session(id)
      {:ok, state} = Session.get_state(id)
      tmux_name = state.tmux_name

      assert :ok = Session.stop(id)
      {:ok, state} = Session.get_state(id)
      assert state.status == :stopped
      assert state.tmux_name == nil

      refute Babysitter.Tmux.session_exists?(tmux_name)
    end
  end

  describe "capture_tmux_output/1" do
    test "captures current tmux pane output", %{session_id: id} do
      {:ok, _pid} = start_session(id)

      {:ok, output} = Session.capture_tmux_output(id)
      assert is_binary(output)

      stop_session(id)
    end
  end

  defp start_session(id, opts \\ []) do
    opts = Keyword.put(opts, :id, id)
    DynamicSupervisor.start_child(Babysitter.SessionSupervisor, {Session, opts})
  end

  defp stop_session(id) do
    if pid = Session.whereis(id) do
      Session.stop(id)
      DynamicSupervisor.terminate_child(Babysitter.SessionSupervisor, pid)
    end
  end
end
