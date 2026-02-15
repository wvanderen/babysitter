defmodule Babysitter.PR do
  @moduledoc """
  GitHub PR integration via gh CLI.

  Provides operations for creating, managing, and merging pull requests
  with template support for titles and bodies.

  ## Prerequisites

  Requires `gh` CLI to be installed and authenticated.
  Run `gh auth login` to set up authentication.

  ## Templates

  PR titles and bodies support TemplateInterpolator placeholders:
  - `{{issue.id}}` - Issue identifier
  - `{{issue.title}}` - Issue title
  - `{{issue.last_handoff.done}}` - Completed items list
  """

  alias Babysitter.TemplateInterpolator

  @type error :: {:error, String.t()}

  @doc """
  Check if gh CLI is available and authenticated.

  ## Examples

      iex> available?()
      true
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd("gh", ["auth", "status"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  end

  @doc """
  Create a pull request.

  ## Options

    * `:title` - PR title (required, supports templates)
    * `:body` - PR body (supports templates)
    * `:base` - Base branch (default: repository default)
    * `:head` - Head branch (default: current branch)
    * `:draft` - Create as draft PR (default: false)
    * `:reviewers` - List of reviewer usernames
    * `:labels` - List of labels to add
    * `:assignees` - List of assignee usernames
    * `:issue` - Issue map for template interpolation
    * `:template_context` - Additional context for templates

  ## Examples

      iex> create(title: "Add feature", body: "Description")
      {:ok, %{url: "https://github.com/...", number: 42}}

      iex> create(title: "{{issue.id}}: {{issue.title}}", issue: %{id: "td-123", title: "Fix"})
      {:ok, %{url: "...", number: 42}}
  """
  @spec create(keyword()) :: {:ok, map()} | error()
  def create(opts) do
    title = Keyword.fetch!(opts, :title)
    body = Keyword.get(opts, :body, "")
    base = Keyword.get(opts, :base)
    head = Keyword.get(opts, :head)
    draft = Keyword.get(opts, :draft, false)
    issue = Keyword.get(opts, :issue)
    template_context = Keyword.get(opts, :template_context, [])

    interpolated_title = interpolate_template(title, issue, template_context)
    interpolated_body = interpolate_template(body, issue, template_context)

    args = build_create_args(interpolated_title, interpolated_body, base, head, draft)

    case System.cmd("gh", ["pr", "create" | args], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_pr_output(output)}

      {output, _code} ->
        {:error, String.trim(output)}
    end
  end

  defp build_create_args(title, body, base, head, draft) do
    args = ["--title", title]

    args =
      if body != "" do
        args ++ ["--body", body]
      else
        args
      end

    args =
      if base do
        args ++ ["--base", base]
      else
        args
      end

    args =
      if head do
        args ++ ["--head", head]
      else
        args
      end

    if draft do
      args ++ ["--draft"]
    else
      args
    end
  end

  @doc """
  Add reviewers to a pull request.

  ## Options

    * `:pr` - PR number or URL (default: current branch's PR)
    * `:reviewers` - List of reviewer usernames (required)

  ## Examples

      iex> add_reviewers(reviewers: ["alice", "bob"])
      :ok

      iex> add_reviewers(pr: 42, reviewers: ["alice"])
      :ok
  """
  @spec add_reviewers(keyword()) :: :ok | error()
  def add_reviewers(opts) do
    reviewers = Keyword.fetch!(opts, :reviewers)
    pr = Keyword.get(opts, :pr)

    args = ["pr", "edit", "--add-reviewer", Enum.join(reviewers, ",")]

    args =
      if pr do
        args ++ [to_string(pr)]
      else
        args
      end

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Add labels to a pull request.

  ## Options

    * `:pr` - PR number or URL (default: current branch's PR)
    * `:labels` - List of labels to add (required)

  ## Examples

      iex> add_labels(labels: ["bug", "priority"])
      :ok

      iex> add_labels(pr: 42, labels: ["enhancement"])
      :ok
  """
  @spec add_labels(keyword()) :: :ok | error()
  def add_labels(opts) do
    labels = Keyword.fetch!(opts, :labels)
    pr = Keyword.get(opts, :pr)

    args = ["pr", "edit", "--add-label", Enum.join(labels, ",")]

    args =
      if pr do
        args ++ [to_string(pr)]
      else
        args
      end

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  List pull requests.

  ## Options

    * `:state` - PR state: :open, :closed, :merged, :all (default: :open)
    * `:limit` - Maximum number to return (default: 30)
    * `:author` - Filter by author
    * `:label` - Filter by label
    * `:json` - Return raw JSON output (default: false)

  ## Examples

      iex> list()
      {:ok, [%{number: 42, title: "Add feature", ...}]}

      iex> list(state: :merged, limit: 10)
      {:ok, [...]}
  """
  @spec list(keyword()) :: {:ok, [map()]} | error()
  def list(opts \\ []) do
    state = Keyword.get(opts, :state, :open)
    limit = Keyword.get(opts, :limit, 30)
    author = Keyword.get(opts, :author)
    label = Keyword.get(opts, :label)
    json = Keyword.get(opts, :json, false)

    args = build_list_args(state, limit, author, label, json)

    case System.cmd("gh", ["pr", "list" | args], stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, parse_list_output(output, json)}

      {output, _code} ->
        {:error, String.trim(output)}
    end
  end

  defp build_list_args(state, limit, author, label, json) do
    args = [
      "--state",
      Atom.to_string(state),
      "--limit",
      Integer.to_string(limit)
    ]

    args =
      if author do
        args ++ ["--author", author]
      else
        args
      end

    args =
      if label do
        args ++ ["--label", label]
      else
        args
      end

    if json do
      args ++ ["--json", "number,title,url,state,author,createdAt"]
    else
      args
    end
  end

  defp parse_list_output(output, true) do
    case Jason.decode(output) do
      {:ok, prs} -> Enum.map(prs, &normalize_pr/1)
      _ -> []
    end
  end

  defp parse_list_output(output, false) do
    output
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.map(&parse_list_line/1)
  end

  defp parse_list_line(line) do
    case String.split(line, "\t", parts: 3) do
      [number, title, url] ->
        %{number: String.to_integer(number), title: title, url: url}

      [number, title] ->
        %{number: String.to_integer(number), title: title}

      _ ->
        %{raw: line}
    end
  end

  @doc """
  Get the PR for the current branch.

  ## Examples

      iex> current()
      {:ok, %{number: 42, title: "Add feature", url: "..."}}

      iex> current()
      {:error, "no pull request found for current branch"}
  """
  @spec current() :: {:ok, map()} | error()
  def current do
    args = ["pr", "view", "--json", "number,title,url,state,body,author"]

    case System.cmd("gh", args, stderr_to_stdout: true) do
      {output, 0} ->
        case Jason.decode(output) do
          {:ok, pr} -> {:ok, normalize_pr(pr)}
          _ -> {:ok, %{}}
        end

      {output, _code} ->
        {:error, String.trim(output)}
    end
  end

  @doc """
  Merge a pull request.

  ## Options

    * `:pr` - PR number or URL (default: current branch's PR)
    * `:method` - Merge method: :merge, :squash, :rebase (default: :squash)
    * `:delete_branch` - Delete branch after merge (default: true)

  ## Examples

      iex> merge()
      :ok

      iex> merge(pr: 42, method: :squash)
      :ok
  """
  @spec merge(keyword()) :: :ok | error()
  def merge(opts \\ []) do
    pr = Keyword.get(opts, :pr)
    method = Keyword.get(opts, :method, :squash)
    delete_branch = Keyword.get(opts, :delete_branch, true)

    args = build_merge_args(pr, method, delete_branch)

    case System.cmd("gh", ["pr", "merge" | args], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_merge_args(pr, method, delete_branch) do
    method_flag =
      case method do
        :merge -> "--merge"
        :squash -> "--squash"
        :rebase -> "--rebase"
      end

    args = [method_flag, "--admin"]

    args =
      if pr do
        args ++ [to_string(pr)]
      else
        args
      end

    if delete_branch do
      args ++ ["--delete-branch"]
    else
      args
    end
  end

  defp interpolate_template(template, nil, _context) when is_binary(template), do: template

  defp interpolate_template(template, issue, context) when is_binary(template) do
    full_context = TemplateInterpolator.build_context(issue, context)
    TemplateInterpolator.interpolate(template, full_context)
  end

  defp interpolate_template(template, _issue, _context), do: template

  defp parse_pr_output(output) do
    output = String.trim(output)

    case Regex.run(~r{https://github\.com/[\w-]+/[\w-]+/pull/(\d+)}, output) do
      [url, number] ->
        %{url: url, number: String.to_integer(number)}

      _ ->
        %{raw: output}
    end
  end

  defp normalize_pr(pr) when is_map(pr) do
    %{
      number: Map.get(pr, "number"),
      title: Map.get(pr, "title", ""),
      url: Map.get(pr, "url", ""),
      state: Map.get(pr, "state", ""),
      body: Map.get(pr, "body", ""),
      author: get_in(pr, ["author", "login"]) || ""
    }
  end

  defp normalize_pr(_), do: %{}
end
