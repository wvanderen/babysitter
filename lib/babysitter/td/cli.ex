defmodule Babysitter.TD.CLI do
  @moduledoc """
  Wrapper for TD CLI write commands using System.cmd.

  Provides programmatic access to td log, handoff, and review commands
  for automated workflow management.
  """

  @td_executable "td"

  @type cli_result :: {:ok, String.t()} | {:error, String.t(), non_neg_integer()}

  @doc """
  Log a progress message to an issue.

  ## Options
    * `:work_dir` - Working directory for td command
    * `:type` - Log type (progress, blocker, decision, hypothesis, tried, result)
  """
  @spec log(String.t(), String.t(), keyword()) :: cli_result()
  def log(issue_id, message, opts \\ [])

  def log(_issue_id, "", _opts), do: {:error, "Message cannot be empty", 1}
  def log(_issue_id, nil, _opts), do: {:error, "Message cannot be empty", 1}

  def log(issue_id, message, opts) when is_binary(issue_id) and is_binary(message) do
    args = build_log_args(issue_id, message, opts)
    execute_td(["log" | args], opts)
  end

  defp build_log_args(issue_id, message, opts) do
    args = [issue_id, message]

    case Keyword.get(opts, :type) do
      nil -> args
      type -> args ++ ["--type", to_string(type)]
    end
  end

  @doc """
  Create a handoff for an issue before review.

  ## Options
    * `:work_dir` - Working directory for td command
    * `:done` - List of completed items
    * `:remaining` - List of remaining items
    * `:decisions` - List of decisions made
    * `:uncertain` - List of uncertainties
    * `:note` - Simple note for handoff
  """
  @spec handoff(String.t(), keyword()) :: cli_result()
  def handoff(issue_id, opts \\ [])

  def handoff(issue_id, opts) when is_binary(issue_id) do
    args = build_handoff_args(issue_id, opts)
    execute_td(["handoff" | args], opts)
  end

  defp build_handoff_args(issue_id, opts) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :note) do
        nil -> args
        note -> args ++ ["--note", note]
      end

    args =
      opts
      |> Keyword.get(:done, [])
      |> Enum.reduce(args, fn item, acc -> acc ++ ["--done", item] end)

    args =
      opts
      |> Keyword.get(:remaining, [])
      |> Enum.reduce(args, fn item, acc -> acc ++ ["--remaining", item] end)

    args =
      opts
      |> Keyword.get(:decisions, [])
      |> Enum.reduce(args, fn item, acc -> acc ++ ["--decision", item] end)

    opts
    |> Keyword.get(:uncertain, [])
    |> Enum.reduce(args, fn item, acc -> acc ++ ["--uncertain", item] end)
  end

  @doc """
  Submit an issue for review.

  ## Options
    * `:work_dir` - Working directory for td command
    * `:reason` - Reason for submitting
    * `:minor` - Mark as minor task (allows self-review)
  """
  @spec review(String.t(), keyword()) :: cli_result()
  def review(issue_id, opts \\ [])

  def review(issue_id, opts) when is_binary(issue_id) do
    args = build_review_args(issue_id, opts)
    execute_td(["review" | args], opts)
  end

  defp build_review_args(issue_id, opts) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :reason) do
        nil -> args
        reason -> args ++ ["--reason", reason]
      end

    if Keyword.get(opts, :minor, false) do
      args ++ ["--minor"]
    else
      args
    end
  end

  @doc """
  Start work on an issue.
  """
  @spec start_issue(String.t(), keyword()) :: cli_result()
  def start_issue(issue_id, opts \\ [])

  def start_issue(issue_id, opts) when is_binary(issue_id) do
    execute_td(["start", issue_id], opts)
  end

  @doc """
  Approve an issue (different session required).
  """
  @spec approve(String.t(), keyword()) :: cli_result()
  def approve(issue_id, opts \\ [])

  def approve(issue_id, opts) when is_binary(issue_id) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :message) do
        nil -> args
        msg -> args ++ ["-m", msg]
      end

    execute_td(["approve" | args], opts)
  end

  @doc """
  Reject an issue.
  """
  @spec reject(String.t(), keyword()) :: cli_result()
  def reject(issue_id, opts \\ [])

  def reject(issue_id, opts) when is_binary(issue_id) do
    args = [issue_id]

    args =
      case Keyword.get(opts, :message) do
        nil -> args
        msg -> args ++ ["-m", msg]
      end

    execute_td(["reject" | args], opts)
  end

  @doc """
  Execute td command and return result.
  """
  @spec execute_td([String.t()], keyword()) :: cli_result()
  def execute_td(args, opts \\ []) do
    work_dir = Keyword.get(opts, :work_dir)
    env = Keyword.get(opts, :env, [])

    opts = [stderr_to_stdout: true]

    opts =
      if work_dir do
        Keyword.put(opts, :cd, work_dir)
      else
        opts
      end

    case System.cmd(@td_executable, args, opts ++ [env: env]) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {output, exit_code} ->
        {:error, String.trim(output), exit_code}
    end
  end

  @doc """
  Check if td CLI is available.
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd(@td_executable, ["--version"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  end
end
