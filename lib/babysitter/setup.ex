defmodule Babysitter.Setup do
  @moduledoc """
  Ensures required directories exist for Babysitter operation.

  This module handles the creation of runtime directories needed by the application:
  - `data/babysitter/` - Session persistence data
  - `data/langgraph/` - LangGraph checkpoints
  - `.babysitter/workflows/` - Workflow definitions
  """

  @required_dirs [
    "data/babysitter",
    "data/langgraph",
    ".babysitter/workflows"
  ]

  @doc """
  Returns the list of required directories.

  ## Examples

      iex> Babysitter.Setup.required_dirs()
      ["data/babysitter", "data/langgraph", ".babysitter/workflows"]
  """
  @spec required_dirs() :: [String.t()]
  def required_dirs, do: @required_dirs

  @doc """
  Ensures all required directories exist using the default list.

  Creates `data/babysitter/`, `data/langgraph/`, and `.babysitter/workflows/`
  if they don't already exist.

  ## Returns

    * `:ok` - Always returns ok

  ## Examples

      iex> Babysitter.Setup.ensure_directories!()
      :ok
  """
  @spec ensure_directories!() :: :ok
  def ensure_directories! do
    ensure_directories(@required_dirs)
  end

  @doc """
  Ensures the specified directories exist.

  Creates each directory in the list if it doesn't already exist.

  ## Parameters

    * `dirs` - List of directory paths to create

  ## Returns

    * `:ok` - Always returns ok

  ## Examples

      iex> Babysitter.Setup.ensure_directories(["tmp/test", "tmp/data"])
      :ok
  """
  @spec ensure_directories([String.t()]) :: :ok
  def ensure_directories(dirs) do
    Enum.each(dirs, &File.mkdir_p/1)
    :ok
  end
end
