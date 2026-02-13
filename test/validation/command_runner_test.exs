defmodule Babysitter.Validation.CommandRunnerTest do
  use ExUnit.Case, async: true

  alias Babysitter.Validation.CommandRunner

  describe "run/2" do
    test "returns ok for successful command" do
      {:ok, result} = CommandRunner.run("echo 'success'")

      assert result.status == :pass
      assert result.exit_code == 0
      assert result.output =~ "success"
    end

    test "returns fail for non-zero exit code" do
      {:ok, result} = CommandRunner.run("exit 1")

      assert result.status == :fail
      assert result.exit_code == 1
    end

    test "respects expected_exit_code option" do
      {:ok, result} = CommandRunner.run("exit 5", expected_exit_code: 5)

      assert result.status == :pass
      assert result.exit_code == 5
    end

    test "detects success pattern in output" do
      {:ok, result} =
        CommandRunner.run(
          "echo 'All tests passed'",
          success_pattern: "tests passed"
        )

      assert result.status == :pass
    end

    test "detects success pattern with regex" do
      {:ok, result} =
        CommandRunner.run(
          "echo '5/5 tests passed'",
          success_pattern: ~r/\d+\/\d+ tests passed/
        )

      assert result.status == :pass
    end

    test "detects failure pattern in output" do
      {:ok, result} =
        CommandRunner.run(
          "echo 'FAIL: something broke'",
          failure_pattern: "FAIL:"
        )

      assert result.status == :fail
    end

    test "failure pattern overrides exit code" do
      {:ok, result} =
        CommandRunner.run(
          "echo 'ERROR: bad thing' && exit 0",
          failure_pattern: "ERROR:"
        )

      assert result.status == :fail
    end

    test "success pattern overrides exit code" do
      {:ok, result} =
        CommandRunner.run(
          "echo 'SUCCESS' && exit 1",
          success_pattern: "SUCCESS"
        )

      assert result.status == :pass
    end

    test "captures output" do
      {:ok, result} = CommandRunner.run("echo 'line1' && echo 'line2'")

      assert result.output =~ "line1"
      assert result.output =~ "line2"
    end

    test "measures duration" do
      {:ok, result} = CommandRunner.run("echo 'test'")

      assert is_integer(result.duration_ms)
      assert result.duration_ms >= 0
    end

    test "handles timeout" do
      {:error, :timeout} = CommandRunner.run("sleep 0.1", timeout: 50)
    end

    test "accepts custom cwd" do
      {:ok, result} = CommandRunner.run("pwd", cwd: "/tmp")

      assert result.output =~ "/tmp"
    end

    test "accepts env variables" do
      {:ok, result} = CommandRunner.run("echo $MY_VAR", env: %{"MY_VAR" => "custom_value"})

      assert result.output =~ "custom_value"
    end
  end

  describe "run_and_validate/2" do
    test "returns :ok for passing command" do
      assert :ok = CommandRunner.run_and_validate("true")
    end

    test "returns {:error, result} for failing command" do
      {:error, result} = CommandRunner.run_and_validate("false")

      assert result.status == :fail
    end
  end

  describe "run_sequence/2" do
    test "runs all commands when all pass" do
      {:ok, results} = CommandRunner.run_sequence(["echo 'one'", "echo 'two'", "echo 'three'"])

      assert length(results) == 3
      assert Enum.all?(results, &(&1.status == :pass))
    end

    test "stops at first failure" do
      {:error, results} =
        CommandRunner.run_sequence([
          "echo 'one'",
          "exit 1",
          "echo 'three'"
        ])

      assert length(results) == 2
      assert hd(results).status == :pass
      assert List.last(results).status == :fail
    end
  end

  describe "run_parallel/2" do
    test "runs all commands in parallel" do
      {:ok, results} =
        CommandRunner.run_parallel([
          "echo 'a'",
          "echo 'b'",
          "echo 'c'"
        ])

      assert length(results) == 3
    end

    test "includes failures in results" do
      {:ok, results} =
        CommandRunner.run_parallel([
          "echo 'pass'",
          "exit 1"
        ])

      statuses = Enum.map(results, & &1.status)
      assert :pass in statuses
      assert :fail in statuses
    end
  end
end
