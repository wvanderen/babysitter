defmodule Babysitter.Git do
  @moduledoc """
  Git integration for version control operations.
  """

  @type error :: {:error, String.t()}

  @doc """
  Stage files for commit (git add).

  ## Options
    * `:all` - Stage all changes (default: false)
    * `:files` - List of specific files to stage (default: nil)

  ## Examples

      iex> Babysitter.Git.add()
      :ok

      iex> Babysitter.Git.add(all: true)
      :ok

      iex> Babysitter.Git.add(files: ["lib/foo.ex", "test/foo_test.exs"])
      :ok
  """
  @spec add(keyword()) :: :ok | error()
  def add(opts \\ []) do
    args = build_add_args(opts)

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_add_args(opts) do
    all = Keyword.get(opts, :all, false)
    files = Keyword.get(opts, :files)

    cond do
      all -> ["add", "--all"]
      files -> ["add" | files]
      true -> ["add", "."]
    end
  end

  @doc """
  Create a commit with the given message.

  ## Options
    * `:message` - Commit message (required)
    * `:allow_empty` - Allow empty commits (default: false)
    * `:no_verify` - Skip pre-commit hooks (default: false)
    * `:amend` - Amend the previous commit (default: false)

  ## Examples

      iex> Babysitter.Git.commit(message: "Add new feature")
      :ok

      iex> Babysitter.Git.commit(message: "Fix bug", no_verify: true)
      :ok
  """
  @spec commit(keyword()) :: :ok | error()
  def commit(opts) do
    message = Keyword.fetch!(opts, :message)
    allow_empty = Keyword.get(opts, :allow_empty, false)
    no_verify = Keyword.get(opts, :no_verify, false)
    amend = Keyword.get(opts, :amend, false)

    args = build_commit_args(message, allow_empty, no_verify, amend)

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_commit_args(message, allow_empty, no_verify, amend) do
    base = ["commit", "-m", message]

    base =
      if allow_empty do
        base ++ ["--allow-empty"]
      else
        base
      end

    base =
      if no_verify do
        base ++ ["--no-verify"]
      else
        base
      end

    if amend do
      base ++ ["--amend"]
    else
      base
    end
  end

  @doc """
  Push commits to remote repository.

  ## Options
    * `:remote` - Remote name (default: "origin")
    * `:branch` - Branch name (default: current branch)
    * `:force` - Force push (default: false)
    * `:set_upstream` - Set upstream for the branch (default: false)

  ## Examples

      iex> Babysitter.Git.push()
      :ok

      iex> Babysitter.Git.push(branch: "feature-branch", set_upstream: true)
      :ok

      iex> Babysitter.Git.push(remote: "upstream", branch: "main")
      :ok
  """
  @spec push(keyword()) :: :ok | error()
  def push(opts \\ []) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch, current_branch())
    force = Keyword.get(opts, :force, false)
    set_upstream = Keyword.get(opts, :set_upstream, false)

    args = build_push_args(remote, branch, force, set_upstream)

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_push_args(remote, branch, force, set_upstream) do
    base = ["push", remote, branch]

    base =
      if force do
        base ++ ["--force"]
      else
        base
      end

    if set_upstream do
      base ++ ["-u"]
    else
      base
    end
  end

  @doc """
  Get the current branch name.

  ## Examples

      iex> Babysitter.Git.current_branch()
      "main"
  """
  @spec current_branch() :: String.t() | error()
  def current_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Check if there are uncommitted changes.

  ## Examples

      iex> Babysitter.Git.has_changes?()
      true
  """
  @spec has_changes?() :: boolean()
  def has_changes? do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} -> output != ""
      _ -> false
    end
  end

  @doc """
  Get the status of the repository.

  ## Examples

      iex> Babysitter.Git.status()
      "On branch main..."
  """
  @spec status() :: String.t() | error()
  def status do
    case System.cmd("git", ["status"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Get the short status (porcelain format).

  ## Examples

      iex> Babysitter.Git.status_short()
      "M lib/foo.ex\n?? lib/bar.ex"
  """
  @spec status_short() :: String.t() | error()
  def status_short do
    case System.cmd("git", ["status", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Get the last commit hash.

  ## Options
    * `:short` - Return short hash (default: false)

  ## Examples

      iex> Babysitter.Git.last_commit()
      "a1b2c3d4e5f6..."

      iex> Babysitter.Git.last_commit(short: true)
      "a1b2c3d"
  """
  @spec last_commit(keyword()) :: String.t() | error()
  def last_commit(opts \\ []) do
    short = Keyword.get(opts, :short, false)
    args = if short, do: ["rev-parse", "--short", "HEAD"], else: ["rev-parse", "HEAD"]

    case System.cmd("git", args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Get the last commit message.

  ## Examples

      iex> Babysitter.Git.last_commit_message()
      "Add new feature"
  """
  @spec last_commit_message() :: String.t() | error()
  def last_commit_message do
    case System.cmd("git", ["log", "-1", "--pretty=%B"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Pull changes from remote repository.

  ## Options
    * `:remote` - Remote name (default: "origin")
    * `:branch` - Branch name (default: current branch)
    * `:rebase` - Use rebase instead of merge (default: false)

  ## Examples

      iex> Babysitter.Git.pull()
      :ok

      iex> Babysitter.Git.pull(rebase: true)
      :ok
  """
  @spec pull(keyword()) :: :ok | error()
  def pull(opts \\ []) do
    remote = Keyword.get(opts, :remote, "origin")
    branch = Keyword.get(opts, :branch, current_branch())
    rebase = Keyword.get(opts, :rebase, false)

    args = build_pull_args(remote, branch, rebase)

    case System.cmd("git", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_pull_args(remote, branch, rebase) do
    base = ["pull", remote, branch]

    if rebase do
      base ++ ["--rebase"]
    else
      base
    end
  end

  @doc """
  Fetch changes from remote repository without merging.

  ## Options
    * `:remote` - Remote name (default: "origin")

  ## Examples

      iex> Babysitter.Git.fetch()
      :ok

      iex> Babysitter.Git.fetch(remote: "upstream")
      :ok
  """
  @spec fetch(keyword()) :: :ok | error()
  def fetch(opts \\ []) do
    remote = Keyword.get(opts, :remote, "origin")

    case System.cmd("git", ["fetch", remote], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Check if the current branch is ahead of its remote.

  ## Examples

      iex> Babysitter.Git.ahead?()
      true
  """
  @spec ahead?() :: boolean()
  def ahead? do
    case System.cmd("git", ["rev-list", "--count", "@{u}..HEAD"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != "0"
      _ -> false
    end
  end

  @doc """
  Check if the current branch is behind its remote.

  ## Examples

      iex> Babysitter.Git.behind?()
      false
  """
  @spec behind?() :: boolean()
  def behind? do
    case System.cmd("git", ["rev-list", "--count", "HEAD..@{u}"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output) != "0"
      _ -> false
    end
  end

  @doc """
  Reset the repository state.

  ## Options
    * `:mode` - Reset mode: :soft, :mixed, :hard (default: :mixed)
    * `:commit` - Commit to reset to (default: "HEAD")

  ## Examples

      iex> Babysitter.Git.reset(mode: :hard)
      :ok

      iex> Babysitter.Git.reset(mode: :soft, commit: "HEAD~1")
      :ok
  """
  @spec reset(keyword()) :: :ok | error()
  def reset(opts \\ []) do
    mode = Keyword.get(opts, :mode, :mixed)
    commit = Keyword.get(opts, :commit, "HEAD")

    mode_flag =
      case mode do
        :soft -> "--soft"
        :mixed -> "--mixed"
        :hard -> "--hard"
      end

    case System.cmd("git", ["reset", mode_flag, commit], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end
end
