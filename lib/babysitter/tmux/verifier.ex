defmodule Babysitter.Tmux.Verifier do
  @moduledoc """
  Verifies tmux availability and version.

  Used at application startup to ensure tmux is installed and accessible.
  """

  @type version :: String.t()

  @doc """
  Verifies that tmux is available on the system.

  ## Returns

    * `{:ok, version}` - tmux is available with its version string
    * `{:error, :tmux_not_found}` - tmux command not found

  ## Examples

      iex> Babysitter.Tmux.Verifier.verify_tmux_available()
      {:ok, "3.4"}

      iex> Babysitter.Tmux.Verifier.verify_tmux_available()
      {:error, :tmux_not_found}
  """
  @spec verify_tmux_available() :: {:ok, version()} | {:error, :tmux_not_found}
  def verify_tmux_available do
    case System.cmd("tmux", ["-V"], stderr_to_stdout: true) do
      {output, 0} ->
        version = parse_version(output)
        {:ok, version}

      {_error, _code} ->
        {:error, :tmux_not_found}
    end
  rescue
    ErlangError -> {:error, :tmux_not_found}
  end

  @doc """
  Verifies tmux availability, raising on failure.

  Same as `verify_tmux_available/0` but raises `RuntimeError` if tmux is not found.
  Useful for fail-fast behavior during application startup.

  ## Returns

    * `version` - the tmux version string

  ## Raises

    * `RuntimeError` - if tmux is not installed

  ## Examples

      iex> Babysitter.Tmux.Verifier.verify_tmux_available!()
      "3.4"
  """
  @spec verify_tmux_available!() :: version() | no_return()
  def verify_tmux_available! do
    case verify_tmux_available() do
      {:ok, version} ->
        version

      {:error, :tmux_not_found} ->
        raise RuntimeError,
          message: "tmux is not installed.\n\n#{installation_instructions()}"
    end
  end

  @doc """
  Returns installation instructions for tmux.

  ## Examples

      iex> Babysitter.Tmux.Verifier.installation_instructions()
      "To install tmux:\\n..."
  """
  @spec installation_instructions() :: String.t()
  def installation_instructions do
    """
    To install tmux:

      macOS (Homebrew):
        brew install tmux

      Ubuntu/Debian:
        sudo apt-get install tmux

      Fedora:
        sudo dnf install tmux

      Arch Linux:
        sudo pacman -S tmux

    For more information, see: https://github.com/tmux/tmux
    """
    |> String.trim()
  end

  @doc """
  Parses tmux version from command output.

  Handles various edge cases in version string parsing.

  ## Examples

      iex> Babysitter.Tmux.Verifier.parse_version("tmux 3.4")
      "3.4"

      iex> Babysitter.Tmux.Verifier.parse_version("  tmux 3.4  ")
      "3.4"

      iex> Babysitter.Tmux.Verifier.parse_version("tmux next-3.4")
      "next-3.4"
  """
  @spec parse_version(String.t()) :: String.t()
  def parse_version(output) do
    output
    |> String.trim()
    |> String.replace(~r/^tmux\s+/i, "")
  end
end
