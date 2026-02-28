defmodule Babysitter.Validation.IntegrationTest do
  use ExUnit.Case, async: false

  alias Babysitter.Validation
  alias Babysitter.StageExecutor

  describe "Validation struct extensions" do
    test "compile type is valid" do
      validation = %Validation{type: :compile}
      assert validation.type == :compile
    end

    test "tests type is valid" do
      validation = %Validation{type: :tests}
      assert validation.type == :tests
    end

    test "command type is valid with command field" do
      validation = %Validation{type: :command, command: "echo test"}
      assert validation.type == :command
      assert validation.command == "echo test"
    end

    test "validation with cwd option" do
      validation = %Validation{type: :compile, cwd: "/tmp"}
      assert validation.cwd == "/tmp"
    end

    test "validation with timeout option" do
      validation = %Validation{type: :compile, timeout: 60_000}
      assert validation.timeout == 60_000
    end

    test "validation with env option" do
      validation = %Validation{type: :command, command: "echo $FOO", env: %{"FOO" => "bar"}}
      assert validation.env == %{"FOO" => "bar"}
    end

    test "runner_type? returns true for compile" do
      assert Validation.runner_type?(%Validation{type: :compile})
    end

    test "runner_type? returns true for tests" do
      assert Validation.runner_type?(%Validation{type: :tests})
    end

    test "runner_type? returns true for command" do
      assert Validation.runner_type?(%Validation{type: :command})
    end

    test "runner_type? returns false for output_contains" do
      refute Validation.runner_type?(%Validation{type: :output_contains})
    end
  end

  describe "Validation factory functions" do
    test "compile/1 creates compile validation" do
      validation = Validation.compile()
      assert validation.type == :compile
    end

    test "compile/1 with language option" do
      validation = Validation.compile(language: :elixir)
      assert validation.language == :elixir
    end

    test "compile/1 with command option" do
      validation = Validation.compile(command: "mix compile")
      assert validation.command == "mix compile"
    end

    test "tests/1 creates tests validation" do
      validation = Validation.tests()
      assert validation.type == :tests
    end

    test "tests/1 with framework option" do
      validation = Validation.tests(framework: :mix)
      assert validation.framework == :mix
    end

    test "command/2 creates command validation" do
      validation = Validation.command("echo hello")
      assert validation.type == :command
      assert validation.command == "echo hello"
    end

    test "command/2 with options" do
      validation = Validation.command("pwd", cwd: "/tmp", timeout: 30_000)
      assert validation.cwd == "/tmp"
      assert validation.timeout == 30_000
    end

    test "lint/1 creates lint validation" do
      validation = Validation.lint(command: "mix format --check-formatted")
      assert validation.type == :lint
      assert validation.command == "mix format --check-formatted"
    end
  end

  describe "StageExecutor.validate_result with runner validations" do
    test "command validation runs and passes for successful command" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [Validation.command("echo hello")]
      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "command validation fails for failing command" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [Validation.command("exit 1")]
      assert {:error, _} = StageExecutor.validate_result(result, validations)
    end

    test "command validation with custom cwd" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [Validation.command("test -f mix.exs", cwd: File.cwd!())]
      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "compile validation runs for this project" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [Validation.compile(command: "mix compile", cwd: File.cwd!())]
      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "tests validation runs for this project" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [
        Validation.tests(
          command: "mix test test/validation/compile_runner_test.exs",
          cwd: File.cwd!()
        )
      ]

      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "mixed validations - runner and output-check" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "hello world",
        exit_code: 0
      }

      validations = [
        Validation.command("echo test"),
        Validation.output_contains("hello")
      ]

      assert :ok = StageExecutor.validate_result(result, validations)
    end

    test "multiple runner validations in sequence" do
      result = %StageExecutor.Result{
        stage_id: "test",
        session_id: "test-session",
        started_at: DateTime.utc_now(),
        finished_at: DateTime.utc_now(),
        output: "",
        exit_code: 0
      }

      validations = [
        Validation.command("echo first"),
        Validation.command("echo second")
      ]

      assert :ok = StageExecutor.validate_result(result, validations)
    end
  end
end
