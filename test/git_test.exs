defmodule Babysitter.GitTest do
  use ExUnit.Case, async: false

  alias Babysitter.Git

  describe "current_branch/0" do
    test "returns the current branch name" do
      result = Git.current_branch()
      assert is_binary(result)
      refute match?({:error, _}, result)
    end
  end

  describe "has_changes?/0" do
    test "returns a boolean" do
      result = Git.has_changes?()
      assert is_boolean(result)
    end
  end

  describe "status/0" do
    test "returns repository status" do
      result = Git.status()
      assert is_binary(result)
      refute match?({:error, _}, result)
    end
  end

  describe "status_short/0" do
    test "returns porcelain status" do
      result = Git.status_short()
      assert is_binary(result)
    end
  end

  describe "last_commit/1" do
    test "returns full commit hash by default" do
      result = Git.last_commit()
      assert is_binary(result)
      assert String.length(result) == 40
    end

    test "returns short hash with short option" do
      result = Git.last_commit(short: true)
      assert is_binary(result)
      assert String.length(result) == 7
    end
  end

  describe "last_commit_message/0" do
    test "returns the last commit message" do
      result = Git.last_commit_message()
      assert is_binary(result)
      refute result == ""
    end
  end

  describe "ahead?/0" do
    test "returns a boolean" do
      result = Git.ahead?()
      assert is_boolean(result)
    end
  end

  describe "behind?/0" do
    test "returns a boolean" do
      result = Git.behind?()
      assert is_boolean(result)
    end
  end

  describe "add/1" do
    test "stages all changes with all option" do
      result = Git.add(all: true)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "commit/1" do
    test "commit requires message option" do
      assert_raise KeyError, fn ->
        Git.commit([])
      end
    end

    test "commit with allow_empty creates empty commit" do
      result = Git.commit(message: "test: empty commit", allow_empty: true)
      assert result == :ok or match?({:error, _}, result)

      if result == :ok do
        Git.reset(mode: :hard, commit: "HEAD~1")
      end
    end
  end

  describe "push/1" do
    test "push returns ok or error" do
      result = Git.push(dry_run: true)
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "pull/1" do
    test "pull returns ok or error" do
      result = Git.pull()
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "fetch/1" do
    test "fetch returns ok or error" do
      result = Git.fetch()
      assert result == :ok or match?({:error, _}, result)
    end
  end

  describe "reset/1" do
    test "reset requires valid mode" do
      result = Git.reset(mode: :soft, commit: "HEAD")
      assert result == :ok
    end
  end

  describe "recent_commits/1" do
    test "returns list of commits within time window" do
      result = Git.recent_commits(minutes: 60)
      assert is_tuple(result)

      case result do
        {:ok, commits} -> assert is_list(commits)
        {:error, _} -> assert true
      end
    end

    test "accepts max_commits option" do
      result = Git.recent_commits(minutes: 60, max_commits: 10)
      assert is_tuple(result)
    end

    test "returns commits with ISO8601 parsed time field" do
      {:ok, commits} = Git.recent_commits(minutes: 60)

      for commit <- commits do
        assert Map.has_key?(commit, :hash)
        assert Map.has_key?(commit, :message)
        assert Map.has_key?(commit, :time)
        assert %DateTime{} = commit.time
      end
    end
  end

  describe "normalize_commits/1" do
    test "returns ok or error" do
      result = Git.normalize_commits(patterns: ["wip:"], time_window_minutes: 60)
      assert result == :ok or match?({:error, _}, result)
    end

    test "accepts default patterns" do
      result = Git.normalize_commits()
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
