defmodule Babysitter.Validation.CommandRunner do
  @moduledoc """
  Executes arbitrary shell commands as validation steps.

  Useful for custom validation logic that doesn't fit into
  standard test or compile checks.

  ## Example

      {:ok, result} = CommandRunner.run("scripts/validate.sh")
      if Result.pass?(result) do
        # validation passed
      end
  """

  alias Babysitter.Validation.Result

  @type command_options :: %{
          optional(:cwd) => String.t(),
          optional(:timeout) => non_neg_integer(),
          optional(:env) => map(),
          optional(:expected_exit_code) => non_neg_integer(),
          optional(:success_pattern) => Regex.t() | String.t(),
          optional(:failure_pattern) => Regex.t() | String.t()
        }

  @default_timeout 60_000
  @default_exit_code 0

  @doc """
  Run a custom command and validate the result.

  ## Options
    * `:cwd` - Working directory (defaults to current)
    * `:timeout` - Timeout in milliseconds (default: 60_000)
    * `:env` - Environment variables to set
    * `:expected_exit_code` - Expected exit code (default: 0)
    * `:success_pattern` - Pattern that indicates success in output
    * `:failure_pattern` - Pattern that indicates failure in output

  ## Returns
    * `{:ok, Result.t()}` - Command completed
    * `{:error, reason}` - Failed to run command
  """
  @spec run(String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def run(command, opts \\ []) do
    cwd = Keyword.get(opts, :cwd)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    env = Keyword.get(opts, :env, %{})
    expected_exit_code = Keyword.get(opts, :expected_exit_code, @default_exit_code)
    success_pattern = Keyword.get(opts, :success_pattern)
    failure_pattern = Keyword.get(opts, :failure_pattern)

    started_at = DateTime.utc_now()

    case execute_command(command, cwd, timeout, env) do
      {:ok, output, exit_code} ->
        finished_at = DateTime.utc_now()

        status =
          determine_status(
            exit_code,
            expected_exit_code,
            output,
            success_pattern,
            failure_pattern
          )

        result = create_result(status, output, exit_code, started_at, finished_at)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Run command and return simple pass/fail.

  Returns `:ok` if validation passed, `{:error, result}` if failed.
  """
  @spec run_and_validate(String.t(), keyword()) :: :ok | {:error, Result.t()}
  def run_and_validate(command, opts \\ []) do
    case run(command, opts) do
      {:ok, %Result{status: :pass}} ->
        :ok

      {:ok, %Result{} = result} ->
        {:error, result}

      {:error, reason} ->
        now = DateTime.utc_now()

        {:error,
         %Result{
           type: :command,
           status: :error,
           error: inspect(reason),
           started_at: now,
           finished_at: now
         }}
    end
  end

  @doc """
  Run multiple commands in sequence.

  Stops at first failure. Returns results of all executed commands.
  """
  @spec run_sequence([String.t()], keyword()) :: {:ok, [Result.t()]} | {:error, [Result.t()]}
  def run_sequence(commands, opts \\ []) do
    results =
      Enum.reduce_while(commands, [], fn command, acc ->
        case run(command, opts) do
          {:ok, %Result{status: :pass} = result} ->
            {:cont, [result | acc]}

          {:ok, %Result{} = result} ->
            {:halt, {:error, Enum.reverse([result | acc])}}

          {:error, reason} ->
            now = DateTime.utc_now()

            result = %Result{
              type: :command,
              status: :error,
              error: inspect(reason),
              started_at: now,
              finished_at: now
            }

            {:halt, {:error, Enum.reverse([result | acc])}}
        end
      end)

    case results do
      {:error, failed_results} -> {:error, failed_results}
      success_results -> {:ok, Enum.reverse(success_results)}
    end
  end

  @doc """
  Run multiple commands in parallel.

  All commands run regardless of individual failures.
  """
  @spec run_parallel([String.t()], keyword()) :: {:ok, [Result.t()]}
  def run_parallel(commands, opts \\ []) do
    results =
      commands
      |> Task.async_stream(
        fn command -> run(command, opts) end,
        timeout: :infinity,
        ordered: false
      )
      |> Enum.map(fn
        {:ok, {:ok, result}} -> result
        {:ok, {:error, reason}} -> error_result(reason)
        {:exit, reason} -> error_result(reason)
      end)

    {:ok, results}
  end

  defp execute_command(command, cwd, timeout, env) do
    base_env = System.get_env() |> Map.to_list()

    extra_env =
      env
      |> Enum.map(fn {k, v} -> {to_string(k), to_string(v)} end)

    opts = [
      env: base_env ++ extra_env
    ]

    opts = if cwd, do: Keyword.put(opts, :cd, cwd), else: opts

    task = Task.async(fn -> System.shell(command, opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {output, exit_code}} ->
        {:ok, output, exit_code}

      nil ->
        {:error, :timeout}

      {:exit, reason} ->
        {:error, reason}
    end
  end

  defp determine_status(exit_code, expected_exit_code, output, success_pattern, failure_pattern) do
    cond do
      failure_pattern && matches_pattern?(output, failure_pattern) ->
        :fail

      success_pattern && matches_pattern?(output, success_pattern) ->
        :pass

      exit_code == expected_exit_code ->
        :pass

      true ->
        :fail
    end
  end

  defp matches_pattern?(output, pattern) when is_binary(pattern) do
    String.contains?(output, pattern)
  end

  defp matches_pattern?(output, %Regex{} = pattern) do
    Regex.match?(pattern, output)
  end

  defp create_result(status, output, exit_code, started_at, finished_at) do
    %Result{
      type: :command,
      status: status,
      output: output,
      exit_code: exit_code,
      started_at: started_at,
      finished_at: finished_at,
      duration_ms: DateTime.diff(finished_at, started_at, :millisecond)
    }
  end

  defp error_result(reason) do
    %Result{
      type: :command,
      status: :error,
      error: inspect(reason),
      started_at: DateTime.utc_now(),
      finished_at: DateTime.utc_now()
    }
  end
end
