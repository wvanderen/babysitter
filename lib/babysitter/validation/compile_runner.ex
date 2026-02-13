defmodule Babysitter.Validation.CompileRunner do
  @moduledoc """
  Executes compile commands and validates results.

  Supports multiple languages/frameworks:
  - Elixir: mix compile
  - Node.js/TypeScript: tsc, npm run build
  - Go: go build
  - Rust: cargo build
  """

  alias Babysitter.Validation.Result

  @type language :: :elixir | :typescript | :go | :rust | :custom

  @type compile_options :: %{
          optional(:language) => language(),
          optional(:command) => String.t(),
          optional(:cwd) => String.t(),
          optional(:timeout) => non_neg_integer(),
          optional(:env) => map()
        }

  @default_timeout 300_000

  @language_commands %{
    elixir: "mix compile --warnings-as-errors",
    typescript: "npx tsc --noEmit",
    go: "go build ./...",
    rust: "cargo build"
  }

  @doc """
  Detect the language for a project.

  Returns `{:ok, language}` or `{:error, :not_detected}`.
  """
  @spec detect_language(String.t() | nil) :: {:ok, language()} | {:error, :not_detected}
  def detect_language(cwd \\ nil) do
    cwd = cwd || File.cwd!()

    cond do
      has_file?(cwd, "mix.exs") -> {:ok, :elixir}
      has_file?(cwd, "tsconfig.json") -> {:ok, :typescript}
      has_file?(cwd, "go.mod") -> {:ok, :go}
      has_file?(cwd, "Cargo.toml") -> {:ok, :rust}
      true -> {:error, :not_detected}
    end
  end

  @doc """
  Run compile check for a project.

  ## Options
    * `:language` - Language to use (auto-detected if not provided)
    * `:command` - Custom command to run (overrides language default)
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 300_000)
    * `:env` - Environment variables to set

  ## Returns
    * `{:ok, Result.t()}` - Compile run completed
    * `{:error, reason}` - Failed to run compile
  """
  @spec run(keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(opts \\ []) do
    cwd = Keyword.get(opts, :cwd)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, %{})

    with {:ok, command} <- get_command(opts) do
      execute_compile_command(command, cwd, timeout, env)
    end
  end

  @doc """
  Run compile check and return pass/fail result.

  Same as `run/1` but returns a simple :ok or {:error, reason}.
  """
  @spec run_and_validate(keyword()) :: :ok | {:error, String.t()}
  def run_and_validate(opts \\ []) do
    case run(opts) do
      {:ok, %Result{status: :pass}} -> :ok
      {:ok, %Result{status: :fail, output: output}} -> {:error, extract_errors(output)}
      {:ok, %Result{status: :error, error: error}} -> {:error, error}
      {:error, reason} -> {:error, inspect(reason)}
    end
  end

  defp get_command(opts) do
    case Keyword.get(opts, :command) do
      nil ->
        case Keyword.get(opts, :language) do
          nil ->
            case detect_language(Keyword.get(opts, :cwd)) do
              {:ok, lang} -> {:ok, Map.get(@language_commands, lang)}
              {:error, _} = error -> error
            end

          lang ->
            {:ok, Map.get(@language_commands, lang)}
        end

      command ->
        {:ok, command}
    end
  end

  defp execute_compile_command(command, cwd, timeout, env) do
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
          {:error, "compile timed out after #{timeout}ms"}

        {:exit, reason} ->
          {:error, "compile crashed: #{inspect(reason)}"}
      end

    finished_at = DateTime.utc_now()

    case result do
      {:ok, output, 0} ->
        {:ok,
         %Result{
           type: :compile,
           status: :pass,
           output: output,
           exit_code: 0,
           started_at: started_at,
           finished_at: finished_at
         }}

      {:ok, output, exit_code} ->
        {:ok,
         %Result{
           type: :compile,
           status: :fail,
           output: output,
           exit_code: exit_code,
           started_at: started_at,
           finished_at: finished_at
         }}

      {:error, reason} ->
        {:ok,
         %Result{
           type: :compile,
           status: :error,
           error: reason,
           started_at: started_at,
           finished_at: finished_at
         }}
    end
  end

  defp has_file?(cwd, filename) do
    File.exists?(Path.join(cwd, filename))
  end

  defp extract_errors(output) do
    lines =
      output
      |> String.split("\n")
      |> Enum.filter(&error_line?/1)

    case lines do
      [] -> output
      errors -> Enum.join(errors, "\n")
    end
  end

  defp error_line?(line) do
    String.contains?(line, "error") or
      String.contains?(line, "Error") or
      String.match?(line, ~r/^\s*\d+\s*\|/)
  end
end
