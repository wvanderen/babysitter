defmodule Babysitter.Validation.CompileRunnerTest do
  use ExUnit.Case, async: true

  alias Babysitter.Validation.{CompileRunner, Result}

  describe "detect_language/1" do
    test "detects Elixir project with mix.exs" do
      cwd = File.cwd!()
      assert {:ok, :elixir} = CompileRunner.detect_language(cwd)
    end

    test "returns error for non-project directory" do
      assert {:error, :not_detected} = CompileRunner.detect_language("/tmp")
    end
  end

  describe "run/1" do
    @tag timeout: 10_000
    test "runs compile for this project" do
      assert {:ok, %Result{} = result} =
               CompileRunner.run(language: :elixir, cwd: File.cwd!(), timeout: 30_000)

      assert result.type == :compile
      assert result.status in [:pass, :fail]
      assert is_binary(result.output)
    end

    @tag timeout: 5_000
    test "runs custom command" do
      assert {:ok, %Result{} = result} =
               CompileRunner.run(command: "echo 'compile ok'", cwd: File.cwd!())

      assert result.status == :pass
      assert String.contains?(result.output, "compile ok")
    end

    @tag timeout: 5_000
    test "captures failing compile output" do
      assert {:ok, %Result{} = result} =
               CompileRunner.run(command: "sh -c 'echo error: failed; exit 1'", cwd: File.cwd!())

      assert result.status == :fail
      assert result.exit_code == 1
    end
  end

  describe "run_and_validate/1" do
    @tag timeout: 5_000
    test "returns :ok for passing compile" do
      assert :ok = CompileRunner.run_and_validate(command: "echo 'pass'", cwd: File.cwd!())
    end

    @tag timeout: 5_000
    test "returns error for failing compile" do
      assert {:error, _output} =
               CompileRunner.run_and_validate(command: "sh -c 'exit 1'", cwd: File.cwd!())
    end
  end
end
