defmodule Babysitter.Validation.TestRunnerTest do
  use ExUnit.Case, async: true

  alias Babysitter.Validation.{TestRunner, Result}

  describe "detect_framework/1" do
    test "detects Elixir project with mix.exs" do
      cwd = File.cwd!()
      assert {:ok, :mix} = TestRunner.detect_framework(cwd)
    end

    test "returns error for non-project directory" do
      assert {:error, :not_detected} = TestRunner.detect_framework("/tmp")
    end
  end

  describe "run/1" do
    @tag timeout: 10_000
    @tag :skip
    test "runs mix test for this project" do
      assert {:ok, %Result{} = result} =
               TestRunner.run(framework: :mix, cwd: File.cwd!(), timeout: 10_000)

      assert result.type == :test
      assert result.status in [:pass, :fail]
      assert is_binary(result.output)
    end

    @tag timeout: 5_000
    test "runs custom command" do
      assert {:ok, %Result{} = result} =
               TestRunner.run(command: "echo 'test passed'", cwd: File.cwd!())

      assert result.status == :pass
      assert String.contains?(result.output, "test passed")
    end

    @tag timeout: 5_000
    test "captures failing test output" do
      assert {:ok, %Result{} = result} =
               TestRunner.run(command: "sh -c 'echo failed; exit 1'", cwd: File.cwd!())

      assert result.status == :fail
      assert result.exit_code == 1
    end
  end

  describe "run_and_validate/1" do
    @tag timeout: 5_000
    test "returns :ok for passing tests" do
      assert :ok = TestRunner.run_and_validate(command: "echo 'pass'", cwd: File.cwd!())
    end

    @tag timeout: 5_000
    test "returns error for failing tests" do
      assert {:error, _output} =
               TestRunner.run_and_validate(command: "sh -c 'exit 1'", cwd: File.cwd!())
    end
  end

  describe "Result" do
    test "pass/3 creates passing result" do
      result = Result.pass(:test, "output")
      assert result.status == :pass
      assert result.type == :test
      assert result.output == "output"
    end

    test "fail/3 creates failing result" do
      result = Result.fail(:compile, "error output", exit_code: 1)
      assert result.status == :fail
      assert result.exit_code == 1
    end

    test "error/3 creates error result" do
      result = Result.error(:test, "command not found")
      assert result.status == :error
      assert result.error == "command not found"
    end

    test "pass?/1 checks status" do
      assert Result.pass?(Result.pass(:test, ""))
      refute Result.pass?(Result.fail(:test, ""))
    end

    test "fail?/1 checks status" do
      assert Result.fail?(Result.fail(:test, ""))
      refute Result.fail?(Result.pass(:test, ""))
    end

    test "duration/1 calculates milliseconds" do
      started = DateTime.utc_now() |> DateTime.add(-1000, :millisecond)
      finished = DateTime.utc_now()

      result = Result.pass(:test, "", started_at: started, finished_at: finished)

      assert Result.duration(result) >= 1000
    end

    test "summary/1 extracts test summary" do
      assert Result.summary(Result.pass(:test, "")) == "PASSED"
      assert Result.summary(Result.fail(:test, "2 failures")) =~ "FAILED"
    end
  end
end
