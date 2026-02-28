defmodule Babysitter.Agent.Ready do
  @moduledoc """
  Detects when agents are ready to receive prompts.

  Polls tmux output for ready indicators (prompt patterns) with configurable
  timeouts per agent type.
  """

  @default_timeout 30_000
  @poll_interval 100

  @doc """
  Wait for an agent to be ready by polling tmux output for a ready pattern.

  ## Parameters

    * `tmux_name` - The tmux session name
    * `pattern` - Regex pattern or string to match in output
    * `timeout` - Timeout in milliseconds (default: 30_000)

  ## Returns

    * `{:ok, :ready}` - Agent is ready
    * `{:error, :timeout}` - Timed out waiting for ready signal

  ## Examples

      iex> Babysitter.Agent.Ready.wait_for_ready("session-1", ">", 5000)
      {:ok, :ready}

      iex> Babysitter.Agent.Ready.wait_for_ready("session-1", "xyz", 100)
      {:error, :timeout}
  """
  @spec wait_for_ready(String.t(), String.t() | Regex.t(), non_neg_integer()) ::
          {:ok, :ready} | {:error, :timeout}
  def wait_for_ready(tmux_name, pattern, timeout \\ @default_timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for_ready(tmux_name, pattern, deadline)
  end

  defp do_wait_for_ready(tmux_name, pattern, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      case Babysitter.Tmux.capture_pane(tmux_name) do
        output when is_binary(output) ->
          case poll_for_pattern(output, pattern) do
            {:ok, true} -> {:ok, :ready}
            {:ok, false} -> poll_again(tmux_name, pattern, deadline)
          end

        {:error, _} ->
          poll_again(tmux_name, pattern, deadline)
      end
    end
  end

  defp poll_again(tmux_name, pattern, deadline) do
    Process.sleep(@poll_interval)
    do_wait_for_ready(tmux_name, pattern, deadline)
  end

  @doc """
  Check if a pattern is present in the output.

  ## Parameters

    * `output` - The tmux output string
    * `pattern` - Regex pattern or string to match

  ## Returns

    * `{:ok, true}` - Pattern found
    * `{:ok, false}` - Pattern not found

  ## Examples

      iex> Babysitter.Agent.Ready.poll_for_pattern("Ready> ", ">")
      {:ok, true}

      iex> Babysitter.Agent.Ready.poll_for_pattern("Some output", "❯|>")
      {:ok, false}
  """
  @spec poll_for_pattern(String.t(), String.t() | Regex.t()) :: {:ok, boolean()}
  def poll_for_pattern(output, pattern) when is_binary(output) do
    regex = to_regex(pattern)
    {:ok, Regex.match?(regex, output)}
  end

  defp to_regex(%Regex{} = regex), do: regex
  defp to_regex(pattern) when is_binary(pattern), do: Regex.compile!(Regex.escape(pattern))

  @doc """
  Get the default timeout value.

  ## Examples

      iex> Babysitter.Agent.Ready.default_timeout()
      30_000
  """
  @spec default_timeout() :: non_neg_integer()
  def default_timeout, do: @default_timeout
end
