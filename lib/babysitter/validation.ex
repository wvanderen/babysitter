defmodule Babysitter.Validation do
  @moduledoc """
  Defines a validation rule for a stage.

  Validations check the output/result of a stage execution
  to determine if it was successful.

  ## Runner Types (execute commands)

  The following validation types actually execute commands:
  - `:compile` - Runs compile command for the project (mix compile, go build, etc.)
  - `:tests` - Runs test command for the project (mix test, go test, pytest, etc.)
  - `:lint` - Runs lint command for the project
  - `:command` - Runs a custom command

  ## Output Check Types (check existing output)

  The following validation types check the output of the stage execution:
  - `:output_contains` - Checks if output contains a string
  - `:output_matches` - Checks if output matches a regex
  - `:exit_code` - Checks the exit code
  - `:output_equals` - Checks if output equals a string
  - `:file_exists` - Checks if a file exists
  - `:file_contains` - Checks if a file contains a pattern
  - `:custom` - Custom validation function
  """

  @derive Jason.Encoder
  @type validation_type ::
          :output_contains
          | :output_matches
          | :exit_code
          | :output_equals
          | :file_exists
          | :file_contains
          | :custom
          | :compile
          | :tests
          | :lint
          | :command

  @type t :: %__MODULE__{
          type: validation_type(),
          pattern: String.t() | Regex.t() | non_neg_integer() | function() | nil,
          path: String.t() | nil,
          negate: boolean(),
          error_message: String.t() | nil,
          command: String.t() | nil,
          cwd: String.t() | nil,
          timeout: non_neg_integer() | nil,
          env: map() | nil,
          language: atom() | nil,
          framework: atom() | nil
        }

  @enforce_keys [:type]
  defstruct [
    :type,
    :path,
    :command,
    :cwd,
    :timeout,
    :env,
    :language,
    :framework,
    pattern: nil,
    negate: false,
    error_message: nil
  ]

  @doc """
  Check if this validation type requires running an external command.

  Runner validations execute commands and should be handled by the
  appropriate runner modules (CompileRunner, TestRunner, CommandRunner).
  """
  @spec runner_type?(t()) :: boolean()
  def runner_type?(%__MODULE__{type: type}) when type in [:compile, :tests, :lint, :command],
    do: true

  def runner_type?(%__MODULE__{}), do: false

  @doc """
  Create a validation that checks if output contains a string.
  """
  @spec output_contains(String.t(), keyword()) :: t()
  def output_contains(pattern, opts \\ []) do
    %__MODULE__{
      type: :output_contains,
      pattern: pattern,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that matches output against a regex.
  """
  @spec output_matches(String.t() | Regex.t(), keyword()) :: t()
  def output_matches(pattern, opts \\ []) do
    pattern = if is_binary(pattern), do: Regex.compile!(pattern), else: pattern

    %__MODULE__{
      type: :output_matches,
      pattern: pattern,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks the exit code.
  """
  @spec exit_code(non_neg_integer() | [non_neg_integer()], keyword()) :: t()
  def exit_code(code, opts \\ []) do
    %__MODULE__{
      type: :exit_code,
      pattern: code,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks if output equals a string.
  """
  @spec output_equals(String.t(), keyword()) :: t()
  def output_equals(expected, opts \\ []) do
    %__MODULE__{
      type: :output_equals,
      pattern: expected,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks if a file exists.
  """
  @spec file_exists(String.t(), keyword()) :: t()
  def file_exists(path, opts \\ []) do
    %__MODULE__{
      type: :file_exists,
      path: path,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that checks if a file contains a pattern.
  """
  @spec file_contains(String.t(), String.t(), keyword()) :: t()
  def file_contains(path, pattern, opts \\ []) do
    %__MODULE__{
      type: :file_contains,
      path: path,
      pattern: pattern,
      negate: Keyword.get(opts, :negate, false),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that runs compile for the project.

  ## Options
    * `:language` - Force a specific language (:elixir, :typescript, :go, :rust)
    * `:command` - Custom compile command (overrides auto-detection)
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 300_000)
    * `:env` - Environment variables to set

  ## Examples

      Validation.compile()
      Validation.compile(language: :elixir)
      Validation.compile(command: "mix compile --warnings-as-errors")
  """
  @spec compile(keyword()) :: t()
  def compile(opts \\ []) do
    %__MODULE__{
      type: :compile,
      language: Keyword.get(opts, :language),
      command: Keyword.get(opts, :command),
      cwd: Keyword.get(opts, :cwd),
      timeout: Keyword.get(opts, :timeout),
      env: Keyword.get(opts, :env),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that runs tests for the project.

  ## Options
    * `:framework` - Force a specific framework (:mix, :npm, :yarn, :go, :pytest)
    * `:command` - Custom test command (overrides auto-detection)
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 300_000)
    * `:env` - Environment variables to set

  ## Examples

      Validation.tests()
      Validation.tests(framework: :mix)
      Validation.tests(command: "mix test --trace")
  """
  @spec tests(keyword()) :: t()
  def tests(opts \\ []) do
    %__MODULE__{
      type: :tests,
      framework: Keyword.get(opts, :framework),
      command: Keyword.get(opts, :command),
      cwd: Keyword.get(opts, :cwd),
      timeout: Keyword.get(opts, :timeout),
      env: Keyword.get(opts, :env),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a validation that runs a custom command.

  ## Options
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 60_000)
    * `:env` - Environment variables to set

  ## Examples

      Validation.command("scripts/validate.sh")
      Validation.command("npm run lint", cwd: "/path/to/project")
  """
  @spec command(String.t(), keyword()) :: t()
  def command(cmd, opts \\ []) do
    %__MODULE__{
      type: :command,
      command: cmd,
      cwd: Keyword.get(opts, :cwd),
      timeout: Keyword.get(opts, :timeout),
      env: Keyword.get(opts, :env),
      error_message: Keyword.get(opts, :error_message)
    }
  end

  @doc """
  Create a lint validation (alias for command with common lint commands).
  """
  @spec lint(keyword()) :: t()
  def lint(opts \\ []) do
    %__MODULE__{
      type: :lint,
      command: Keyword.get(opts, :command),
      cwd: Keyword.get(opts, :cwd),
      timeout: Keyword.get(opts, :timeout),
      env: Keyword.get(opts, :env),
      error_message: Keyword.get(opts, :error_message, "Linting failed")
    }
  end

  @doc """
  Run the validation against output and exit code.

  Note: This function is for output-check validations. Runner validations
  (compile, tests, command) should be handled by StageExecutor.validate_result/2.
  """
  @spec run(t(), String.t(), non_neg_integer()) :: :ok | {:error, String.t()}
  def run(%__MODULE__{} = validation, output, exit_code) do
    result = do_validate(validation, output, exit_code)

    if validation.negate do
      case result do
        :ok -> error(validation, "negated validation passed")
        {:error, _} -> :ok
      end
    else
      result
    end
  end

  defp do_validate(%__MODULE__{type: :output_contains, pattern: pattern} = v, output, _exit_code) do
    if String.contains?(output, pattern) do
      :ok
    else
      error(v, "output does not contain '#{pattern}'")
    end
  end

  defp do_validate(%__MODULE__{type: :output_matches, pattern: regex} = v, output, _exit_code) do
    if Regex.match?(regex, output) do
      :ok
    else
      error(v, "output does not match pattern")
    end
  end

  defp do_validate(%__MODULE__{type: :exit_code, pattern: expected} = v, _output, exit_code) do
    codes = if is_list(expected), do: expected, else: [expected]

    if exit_code in codes do
      :ok
    else
      error(v, "exit code #{exit_code} not in expected #{inspect(codes)}")
    end
  end

  defp do_validate(%__MODULE__{type: :output_equals, pattern: expected} = v, output, _exit_code) do
    if output == expected do
      :ok
    else
      error(v, "output does not equal expected value")
    end
  end

  defp do_validate(%__MODULE__{type: :custom, pattern: func}, output, exit_code)
       when is_function(func, 2) do
    func.(output, exit_code)
  end

  defp do_validate(%__MODULE__{type: :file_exists, path: path} = v, _output, _exit_code) do
    if File.exists?(path) do
      :ok
    else
      error(v, "file does not exist: #{path}")
    end
  end

  defp do_validate(
         %__MODULE__{type: :file_contains, path: path, pattern: pattern} = v,
         _output,
         _exit_code
       ) do
    with true <- File.exists?(path),
         {:ok, content} <- File.read(path) do
      if String.contains?(content, pattern) do
        :ok
      else
        error(v, "file #{path} does not contain '#{pattern}'")
      end
    else
      false -> error(v, "file does not exist: #{path}")
      {:error, reason} -> error(v, "failed to read file #{path}: #{inspect(reason)}")
    end
  end

  defp do_validate(%__MODULE__{type: type} = v, _output, _exit_code) do
    error(v, "unsupported validation type: #{type}")
  end

  defp error(validation, message) do
    {:error, validation.error_message || message}
  end
end
