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
  end
end
