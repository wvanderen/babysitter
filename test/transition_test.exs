defmodule Babysitter.TransitionTest do
  use ExUnit.Case, async: true

  alias Babysitter.Transition

  describe "always/1" do
    test "matches any result" do
      t = Transition.always(:next)
      assert Transition.matches?(t, :success, "output", 0)
      assert Transition.matches?(t, :failure, "output", 1)
      assert Transition.matches?(t, :timeout, "", 0)
    end
  end

  describe "on_success/1" do
    test "matches only success" do
      t = Transition.on_success(:next)
      assert Transition.matches?(t, :success, "output", 0)
      refute Transition.matches?(t, :failure, "output", 1)
    end
  end

  describe "on_failure/1" do
    test "matches only failure" do
      t = Transition.on_failure(:retry)
      refute Transition.matches?(t, :success, "output", 0)
      assert Transition.matches?(t, :failure, "output", 1)
    end
  end

  describe "on_timeout/1" do
    test "matches only timeout" do
      t = Transition.on_timeout(:abort)
      assert Transition.matches?(t, :timeout, "", 0)
      refute Transition.matches?(t, :success, "", 0)
    end
  end

  describe "when_output_contains/2" do
    test "matches when output contains pattern" do
      t = Transition.when_output_contains(:next, "continue")
      assert Transition.matches?(t, :success, "please continue", 0)
      refute Transition.matches?(t, :success, "stop here", 0)
    end
  end

  describe "when_output_matches/2" do
    test "matches when output matches regex" do
      t = Transition.when_output_matches(:next, ~r/next: \w+/)
      assert Transition.matches?(t, :success, "next: step2", 0)
      refute Transition.matches?(t, :success, "invalid", 0)
    end
  end

  describe "when_exit_code/2" do
    test "matches specific exit code" do
      t = Transition.when_exit_code(:retry, 2)
      assert Transition.matches?(t, :failure, "output", 2)
      refute Transition.matches?(t, :failure, "output", 1)
    end
  end

  describe "when_custom/2" do
    test "evaluates custom function" do
      t =
        Transition.when_custom(:next, fn output, _exit ->
          String.starts_with?(output, "OK")
        end)

      assert Transition.matches?(t, :success, "OK: done", 0)
      refute Transition.matches?(t, :success, "FAIL: error", 0)
    end
  end
end
