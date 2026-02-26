defmodule Babysitter.TDTest.VerifyIntegrationTest do
  use ExUnit.Case, async: true

  alias Babysitter.TDTest.VerifyIntegration

  describe "verify/0" do
    test "returns success tuple with task reference" do
      assert {:ok, message} = VerifyIntegration.verify()
      assert message =~ "td-924bd6"
      assert message =~ "verified"
    end
  end

  describe "task_id/0" do
    test "returns the td task identifier" do
      assert VerifyIntegration.task_id() == "td-924bd6"
    end
  end

  describe "task_title/0" do
    test "returns the task title" do
      assert VerifyIntegration.task_title() == "td-test-writer-756116"
    end
  end
end
