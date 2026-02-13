defmodule Babysitter.Tmux do
  @moduledoc """
  Tmux integration for managing terminal sessions.
  """

  @type session_name :: String.t()
  @type command_output :: {String.t(), exit_status :: non_neg_integer()}
  @type error :: {:error, String.t()}

  @doc """
  Create a new tmux session with the given name.

  ## Options
    * `:window` - Window name (default: same as session name)
    * `:detached` - Create session in detached mode (default: true)
    * `:shell` - Shell command to run (default: default shell)

  ## Examples

      iex> Babysitter.Tmux.create_session("my-session")
      :ok

      iex> Babysitter.Tmux.create_session("my-session", shell: "/bin/bash")
      :ok
  """
  @spec create_session(session_name(), keyword()) :: :ok | error()
  def create_session(name, opts \\ []) do
    window = Keyword.get(opts, :window, name)
    detached = Keyword.get(opts, :detached, true)
    shell = Keyword.get(opts, :shell)

    args = build_new_args(name, window, detached, shell)

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  defp build_new_args(name, window, detached, shell) do
    base = ["new-session", "-s", name, "-n", window]

    base =
      if detached do
        base ++ ["-d"]
      else
        base
      end

    if shell do
      base ++ [shell]
    else
      base
    end
  end

  @doc """
  Kill a tmux session by name.

  ## Examples

      iex> Babysitter.Tmux.kill_session("my-session")
      :ok

      iex> Babysitter.Tmux.kill_session("nonexistent")
      {:error, "no session found: nonexistent"}
  """
  @spec kill_session(session_name()) :: :ok | error()
  def kill_session(name) do
    case System.cmd("tmux", ["kill-session", "-t", name], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Check if a tmux session exists.

  ## Examples

      iex> Babysitter.Tmux.session_exists?("my-session")
      true

      iex> Babysitter.Tmux.session_exists?("nonexistent")
      false
  """
  @spec session_exists?(session_name()) :: boolean()
  def session_exists?(name) do
    case System.cmd("tmux", ["has-session", "-t=#{name}"], stderr_to_stdout: true) do
      {_output, 0} -> true
      _output -> false
    end
  end

  @doc """
  List all tmux sessions.

  ## Examples

      iex> Babysitter.Tmux.list_sessions()
      ["session1", "session2"]
  """
  @spec list_sessions() :: [session_name()]
  def list_sessions do
    case System.cmd("tmux", ["list-sessions", "-F", "\#{session_name}"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> String.split("\n", trim: true)

      _ ->
        []
    end
  end

  @doc """
  Send keys/commands to a tmux session.

  ## Options
    * `:pane` - Target pane (default: 0)
    * `:enter` - Send Enter after keys (default: true)

  ## Examples

      iex> Babysitter.Tmux.send_keys("my-session", "ls -la")
      :ok
  """
  @spec send_keys(session_name(), String.t(), keyword()) :: :ok | error()
  def send_keys(session_name, keys, opts \\ []) do
    pane = Keyword.get(opts, :pane, 0)
    enter = Keyword.get(opts, :enter, true)

    target = "#{session_name}.#{pane}"

    args =
      if enter do
        ["send-keys", "-t", target, keys, "Enter"]
      else
        ["send-keys", "-t", target, keys]
      end

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Capture output from a tmux pane.

  ## Options
    * `:pane` - Target pane (default: 0)
    * `:lines` - Number of lines to capture (default: all visible)

  ## Examples

      iex> Babysitter.Tmux.capture_pane("my-session")
      "output from the session..."
  """
  @spec capture_pane(session_name(), keyword()) :: String.t() | error()
  def capture_pane(session_name, opts \\ []) do
    pane = Keyword.get(opts, :pane, 0)
    lines = Keyword.get(opts, :lines)

    target = "#{session_name}.#{pane}"

    args =
      if lines do
        ["capture-pane", "-t", target, "-p", "-S", "-#{lines}"]
      else
        ["capture-pane", "-t", target, "-p"]
      end

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Set up pipe-pane to capture session output to a file.

  ## Examples

      iex> Babysitter.Tmux.pipe_pane("my-session", "/tmp/output.log")
      :ok

      iex> Babysitter.Tmux.pipe_pane("my-session", nil)
      :ok  # Disables pipe
  """
  @spec pipe_pane(session_name(), String.t() | nil, keyword()) :: :ok | error()
  def pipe_pane(session_name, pipe_file, opts \\ []) do
    pane = Keyword.get(opts, :pane, 0)
    target = "#{session_name}.#{pane}"

    args =
      if pipe_file do
        ["pipe-pane", "-t", target, "-o", "cat >> #{pipe_file}"]
      else
        ["pipe-pane", "-t", target]
      end

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Resize a tmux window.

  ## Options
    * `:width` - Window width (default: 120)
    * `:height` - Window height (default: 40)
  """
  @spec resize_window(session_name(), keyword()) :: :ok | error()
  def resize_window(session_name, opts \\ []) do
    width = Keyword.get(opts, :width, 120)
    height = Keyword.get(opts, :height, 40)

    args = ["resize-window", "-t", session_name, "-x", to_string(width), "-y", to_string(height)]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end

  @doc """
  Rename a tmux session.

  ## Examples

      iex> Babysitter.Tmux.rename_session("old-name", "new-name")
      :ok
  """
  @spec rename_session(session_name(), session_name()) :: :ok | error()
  def rename_session(old_name, new_name) do
    case System.cmd("tmux", ["rename-session", "-t", old_name, new_name], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, _code} -> {:error, String.trim(output)}
    end
  end
end
