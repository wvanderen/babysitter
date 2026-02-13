defmodule Babysitter.Validation.TestRunner do
  @moduledoc """
  Executes test commands and validates results.

  Supports multiple test frameworks:
  - Elixir: mix test
  - Node.js: npm test, yarn test
  - Go: go test ./...
  - Python: pytest, python -m pytest
  """

  alias Babysitter.Validation.Result

  @type framework :: :mix | :npm | :yarn | :go | :pytest | :custom

  @type test_options :: %{
          optional(:framework) => framework(),
          optional(:command) => String.t(),
          optional(:cwd) => String.t(),
          optional(:timeout) => non_neg_integer(),
          optional(:env) => map()
        }

  @default_timeout 300_000

  @framework_commands %{
    mix: "mix test",
    npm: "npm test",
    yarn: "yarn test",
    go: "go test ./...",
    pytest: "pytest"
  }

  @doc """
  Detect the test framework for a project.

  Returns `{:ok, framework}` or `{:error, :not_detected}`.
  """
  @spec detect_framework(String.t() | nil) :: {:ok, framework()} | {:error, :not_detected}
  def detect_framework(cwd \\ nil) do
    cwd = cwd || File.cwd!()

    cond do
      has_file?(cwd, "mix.exs") -> {:ok, :mix}
      has_file?(cwd, "package.json") -> {:ok, :npm}
      has_file?(cwd, "go.mod") -> {:ok, :go}
      has_file?(cwd, "pytest.ini") or has_file?(cwd, "setup.py") -> {:ok, :pytest}
      true -> {:error, :not_detected}
    end
  end

  @doc """
  Run tests for a project.

  ## Options
    * `:framework` - Test framework to use (auto-detected if not provided)
    * `:command` - Custom command to run (overrides framework default)
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 300_000)
    * `:env` - Environment variables to set

  ## Returns
    * `{:ok, Result.t()}` - Test run completed
    * `{:error, reason}` - Failed to run tests
  """
  @spec run(keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(opts \\ []) do
    cwd = Keyword.get(opts, :cwd)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, %{})

    with {:ok, command} <- get_command(opts) do
      execute_test_command(command, cwd, timeout, env)
    end
  end

  @doc """
  Run tests and return pass/fail result.

  Same as `run/1` but returns a simple :ok or {:error, reason}.
  """
  @spec run_and_validate(keyword()) :: :ok | {:error, String.t()}
  def run_and_validate(opts \\ []) do
    case run(opts) do
      {:ok, %Result{status: :pass}} -> :ok
      {:ok, %Result{status: :fail, output: output}} -> {:error, output}
      {:ok, %Result{status: :error, error: error}} -> {:error, error}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp get_command(opts) do
    case Keyword.get(opts, :command) do
      nil ->
        case Keyword.get(opts, :framework) do
          nil ->
            case detect_framework(Keyword.get(opts, :cwd)) do
              {:ok, framework} -> {:ok, Map.get(@framework_commands, framework)}
              {:error, _} = error -> error
            end

          framework ->
            {:ok, Map.get(@framework_commands, framework)}
        end

      command ->
        {:ok, command}
    end
  end

  defp execute_test_command(command, cwd, timeout, env) do
    started_at = DateTime.utc_now()

    base_env = System.get_env() |> Map.to_list()

    extra_env =
      env
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    opts = [
      env: base_env ++ extra_env,
      cd: cwd
    ]

    task = Task.async(fn -> System.shell(command, opts) end)

    result =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, exit_code}} ->
          {:ok, output, exit_code}

        nil ->
          {:error, "command timed out after #{timeout}ms"}

        {:exit, reason} ->
          {:error, "command crashed: #{inspect(reason)}"}
      end

    finished_at = DateTime.utc_now()

    case result do
      {:ok, output, 0} ->
        {:ok,
         %Result{
           type: :test,
           status: :pass,
           output: output,
           exit_code: 0,
           started_at: started_at,
           finished_at: finished_at
         }}

      {:ok, output, exit_code} ->
        {:ok,
         %Result{
           type: :test,
           status: :fail,
           output: output,
           exit_code: exit_code,
           started_at: started_at,
           finished_at: finished_at
         }}

      {:error, reason} ->
        {:ok,
         %Result{
           type: :test,
           status: :error,
           error: inspect(reason),
           started_at: started_at,
           finished_at: finished_at
         }}
    end
  end

  defp has_file?(cwd, filename) do
    File.exists?(Path.join(cwd, filename))
  end
end
