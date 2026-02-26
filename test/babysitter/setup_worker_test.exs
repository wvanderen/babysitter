defmodule Babysitter.SetupWorkerTest do
  use ExUnit.Case, async: false

  alias Babysitter.SetupWorker

  describe "start_link/1" do
    test "worker is running as part of supervision tree" do
      pid = Process.whereis(SetupWorker)
      assert is_pid(pid)
    end
  end

  describe "init/1" do
    test "returns ok tuple when setup succeeds" do
      assert {:ok, _state} = SetupWorker.init([])
    end

    test "returns error with instructions when tmux is not available" do
      original_path = System.get_env("PATH")

      try do
        System.put_env("PATH", "/nonexistent")

        assert {:error, instructions} = SetupWorker.init([])
        assert instructions =~ "tmux"
        assert instructions =~ "install"
      after
        System.put_env("PATH", original_path)
      end
    end
  end
end
