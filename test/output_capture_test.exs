defmodule Babysitter.OutputCaptureTest do
  use ExUnit.Case, async: false
  alias Babysitter.{OutputCapture, Tmux}
  @moduletag :tmux

  describe "start_capture/1" do
    test "starts capture process for existing session" do
      session_name = "test-capture-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      assert :ok = Tmux.create_session(session_name)
      try do
        assert {:ok, pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        assert is_pid(pid)
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end

    test "returns error for non-existent session" do
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      assert {:error, :session_not_found} = OutputCapture.start_capture(id: capture_id, session_name: "nonexistent-session-xyz")
    end
  end

  describe "get_output/1" do
    test "returns buffered output" do
      session_name = "test-output-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        :ok = Tmux.send_keys(session_name, "echo test-output-123")
        Process.sleep(300)
        assert {:ok, output} = OutputCapture.get_output(capture_id)
        assert is_binary(output)
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end

    test "returns error for non-existent capture" do
      assert {:error, :not_found} = OutputCapture.get_output("nonexistent-capture")
    end
  end

  describe "clear_buffer/1" do
    test "clears the output buffer" do
      session_name = "test-clear-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        :ok = Tmux.send_keys(session_name, "echo hello-world-unique-123")
        Process.sleep(300)
        {:ok, output_before} = OutputCapture.get_output(capture_id)
        assert output_before =~ "hello-world-unique-123"
        assert :ok = OutputCapture.clear_buffer(capture_id)
        {:ok, output_after} = OutputCapture.get_output(capture_id)
        assert byte_size(output_after) < byte_size(output_before)
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end

  describe "pause/1 and resume/1" do
    test "pauses and resumes output capture" do
      session_name = "test-pause-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        assert :ok = OutputCapture.pause(capture_id)
        assert :ok = OutputCapture.resume(capture_id)
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end

  describe "subscribe/1 and unsubscribe/1" do
    test "subscribes to output notifications" do
      session_name = "test-subscribe-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        assert :ok = OutputCapture.subscribe(capture_id)
        assert :ok = OutputCapture.unsubscribe(capture_id)
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end

  describe "stop_capture/1" do
    test "stops capture and cleans up" do
      session_name = "test-stop-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        assert :ok = OutputCapture.stop_capture(capture_id)
        assert {:error, :not_found} = OutputCapture.get_output(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end

  describe "get_state/1" do
    test "returns current state" do
      session_name = "test-state-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name)
        assert {:ok, state} = OutputCapture.get_state(capture_id)
        assert state.id == capture_id
        assert state.session_name == session_name
        assert state.status == :running
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end

  describe "max_buffer_size" do
    test "respects max buffer size" do
      session_name = "test-buffer-#{:erlang.unique_integer([:positive])}"
      capture_id = "capture-#{:erlang.unique_integer([:positive])}"
      :ok = Tmux.create_session(session_name)
      try do
        {:ok, _pid} = OutputCapture.start_capture(id: capture_id, session_name: session_name, max_buffer_size: 100)
        Process.sleep(100)
        {:ok, state} = OutputCapture.get_state(capture_id)
        assert state.max_buffer_size == 100
        assert :ok = OutputCapture.stop_capture(capture_id)
      after
        if Tmux.session_exists?(session_name), do: Tmux.kill_session(session_name)
      end
    end
  end
end
