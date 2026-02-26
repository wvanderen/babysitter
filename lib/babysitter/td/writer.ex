defmodule Babysitter.TD.Writer do
  @moduledoc """
  High-level API for writing context to td.

  Provides functions for creating handoffs, adding logs, and managing
  review status for td issues.

  ## Usage

      # Create a handoff
      Writer.create_handoff("td-123", done: ["Task 1"], remaining: ["Task 2"])

      # Add a log
      Writer.add_log("td-123", "Progress update", type: "progress")

      # Submit for review
      Writer.submit_for_review("td-123", reason: "Implementation complete")

      # Write full context
      Writer.write_context("td-123", %{done: ["..."], remaining: ["..."]})
  """

  alias Babysitter.TD.CLI

  @type write_result :: {:ok, String.t()} | {:error, String.t(), non_neg_integer()}

  @type context :: %{
          optional(:done) => [String.t()],
          optional(:remaining) => [String.t()],
          optional(:uncertain) => [String.t()],
          optional(:decisions) => [String.t()],
          optional(:note) => String.t()
        }

  @doc """
  Create a handoff for an issue.

  ## Options

    * `:done` - List of completed items
    * `:remaining` - List of remaining items
    * `:uncertain` - List of items needing clarification
    * `:decisions` - List of decisions made
    * `:note` - Simple note for handoff

  ## Examples

      iex> Writer.create_handoff("td-123", done: ["Fixed bug"], remaining: ["Add tests"])
      {:ok, "Handoff created"}

      iex> Writer.create_handoff("td-123", note: "Session ended, continuing tomorrow")
      {:ok, "Handoff created"}
  """
  @spec create_handoff(String.t(), keyword() | context()) :: write_result()
  def create_handoff(issue_id, opts) when is_binary(issue_id) do
    CLI.handoff(issue_id, normalize_opts(opts))
  end

  @doc """
  Add a log entry to an issue.

  ## Options

    * `:type` - Log type: progress, blocker, decision, hypothesis, tried, result

  ## Examples

      iex> Writer.add_log("td-123", "Halfway done", type: "progress")
      {:ok, "Log added"}

      iex> Writer.add_log("td-123", "API down", type: "blocker")
      {:ok, "Log added"}
  """
  @spec add_log(String.t(), String.t(), keyword()) :: write_result()
  def add_log(issue_id, message, opts \\ [])

  def add_log(_issue_id, "", _opts), do: {:error, "Message cannot be empty", 1}
  def add_log(_issue_id, nil, _opts), do: {:error, "Message cannot be empty", 1}

  def add_log(issue_id, message, opts) when is_binary(issue_id) and is_binary(message) do
    CLI.log(issue_id, message, opts)
  end

  @doc """
  Submit an issue for review.

  Prerequisite: A handoff must exist for the issue.

  ## Options

    * `:reason` - Reason for submitting
    * `:minor` - Mark as minor task (allows self-review)

  ## Examples

      iex> Writer.submit_for_review("td-123", reason: "Feature complete")
      {:ok, "Submitted for review"}
  """
  @spec submit_for_review(String.t(), keyword()) :: write_result()
  def submit_for_review(issue_id, opts \\ []) when is_binary(issue_id) do
    CLI.review(issue_id, opts)
  end

  @doc """
  Write full context to an issue.

  Creates a handoff with the provided context and optionally adds a log.

  ## Options

    * `:message` - Optional log message to add with the context

  ## Examples

      iex> Writer.write_context("td-123", %{done: ["Task 1"], remaining: ["Task 2"]}, message: "Session done")
      {:ok, "Context written"}
  """
  @spec write_context(String.t(), context(), keyword()) :: write_result()
  def write_context(issue_id, context, opts \\ []) when is_binary(issue_id) do
    handoff_opts = [
      done: Map.get(context, :done, []),
      remaining: Map.get(context, :remaining, []),
      uncertain: Map.get(context, :uncertain, []),
      decisions: Map.get(context, :decisions, []),
      note: Map.get(context, :note)
    ]

    result = create_handoff(issue_id, handoff_opts)

    case {result, Keyword.get(opts, :message)} do
      {{:ok, _}, nil} ->
        result

      {{:ok, _}, message} when is_binary(message) ->
        add_log(issue_id, message, type: "progress")
        result

      _ ->
        result
    end
  end

  @doc """
  Update the status of an issue.

  ## Actions

    * `:blocked` - Block the issue
    * `:start` - Start work on the issue
    * `:approve` - Approve the issue (different session required)
    * `:reject` - Reject the issue

  ## Options

    * `:reason` - Reason for the status change
    * `:message` - Message for approve/reject

  ## Examples

      iex> Writer.update_status("td-123", :blocked, reason: "Waiting for API")
      {:ok, "Issue blocked"}

      iex> Writer.update_status("td-123", :start)
      {:ok, "Issue started"}
  """
  @spec update_status(String.t(), atom(), keyword()) :: write_result()
  def update_status(issue_id, action, opts \\ [])

  def update_status(issue_id, :blocked, opts) do
    CLI.block(issue_id, reason: Keyword.get(opts, :reason))
  end

  def update_status(issue_id, :start, _opts) do
    CLI.start_issue(issue_id)
  end

  def update_status(issue_id, :approve, opts) do
    CLI.approve(issue_id, message: Keyword.get(opts, :message))
  end

  def update_status(issue_id, :reject, opts) do
    CLI.reject(issue_id, message: Keyword.get(opts, :message))
  end

  defp normalize_opts(opts) when is_map(opts) do
    [
      done: Map.get(opts, :done, []),
      remaining: Map.get(opts, :remaining, []),
      uncertain: Map.get(opts, :uncertain, []),
      decisions: Map.get(opts, :decisions, []),
      note: Map.get(opts, :note)
    ]
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
end
