defmodule Babysitter.TD.Client do
  @moduledoc """
  Client for reading issues from TD SQLite database.

  Provides read-only access to the .todos/issues.db file.
  """

  alias Babysitter.TD.{Handoff, Issue, Repo}
  import Ecto.Query

  @doc """
  List all issues.
  """
  @spec list_issues(keyword()) :: [Issue.t()]
  def list_issues(opts \\ []) do
    status = Keyword.get(opts, :status)
    issue_type = Keyword.get(opts, :type)
    priority = Keyword.get(opts, :priority)
    parent_id = Keyword.get(opts, :parent_id)

    query = from(i in Issue, order_by: [desc: i.updated_at])

    query =
      if status do
        where(query, [i], i.status == ^status)
      else
        query
      end

    query =
      if issue_type do
        where(query, [i], i.type == ^issue_type)
      else
        query
      end

    query =
      if priority do
        where(query, [i], i.priority == ^priority)
      else
        query
      end

    query =
      if parent_id != nil do
        where(query, [i], i.parent_id == ^parent_id)
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Get a single issue by ID.
  """
  @spec get_issue(String.t()) :: Issue.t() | nil
  def get_issue(id) do
    Repo.get(Issue, id)
  end

  @doc """
  Get issue by ID or raise.
  """
  @spec get_issue!(String.t()) :: Issue.t()
  def get_issue!(id) do
    Repo.get!(Issue, id)
  end

  @doc """
  List open issues.
  """
  @spec open_issues() :: [Issue.t()]
  def open_issues do
    from(i in Issue, where: i.status == "open", order_by: [desc: i.updated_at])
    |> Repo.all()
  end

  @doc """
  List issues in review.
  """
  @spec review_issues() :: [Issue.t()]
  def review_issues do
    from(i in Issue, where: i.status == "in_review", order_by: [desc: i.updated_at])
    |> Repo.all()
  end

  @doc """
  List issues by priority.
  """
  @spec by_priority(String.t()) :: [Issue.t()]
  def by_priority(priority) do
    from(i in Issue, where: i.priority == ^priority, order_by: [desc: i.updated_at])
    |> Repo.all()
  end

  @doc """
  Get child issues of a parent.
  """
  @spec children(String.t()) :: [Issue.t()]
  def children(parent_id) do
    from(i in Issue, where: i.parent_id == ^parent_id, order_by: [asc: i.created_at])
    |> Repo.all()
  end

  @doc """
  Search issues by title or description.
  """
  @spec search(String.t()) :: [Issue.t()]
  def search(term) do
    pattern = "%#{term}%"

    from(i in Issue,
      where: like(i.title, ^pattern) or like(i.description, ^pattern),
      order_by: [desc: i.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Count issues by status.
  """
  @spec count_by_status(String.t()) :: non_neg_integer()
  def count_by_status(status) do
    from(i in Issue, where: i.status == ^status)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Get the latest handoff for an issue.
  """
  @spec get_latest_handoff(String.t()) :: Handoff.t() | nil
  def get_latest_handoff(issue_id) do
    from(h in Handoff,
      where: h.issue_id == ^issue_id,
      order_by: [desc: h.timestamp],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Get all handoffs for an issue.
  """
  @spec get_handoffs(String.t()) :: [Handoff.t()]
  def get_handoffs(issue_id) do
    from(h in Handoff,
      where: h.issue_id == ^issue_id,
      order_by: [desc: h.timestamp]
    )
    |> Repo.all()
  end

  @doc """
  Get handoff by ID.
  """
  @spec get_handoff(String.t()) :: Handoff.t() | nil
  def get_handoff(id) do
    Repo.get(Handoff, id)
  end
end
