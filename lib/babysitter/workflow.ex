defmodule Babysitter.Workflow do
  @moduledoc """
  Workflow definition struct for type-safe workflow representation.

  Workflows define a sequence of stages with transitions and configuration
  for automated agent execution.
  """

  alias Babysitter.Stage

  @derive {Jason.Encoder, only: [:id, :name, :stages, :intelligence, :transitions, :description]}

  @typedoc "Intelligence level for workflow execution"
  @type intelligence :: :dumb | :smart | :hybrid

  @typedoc "Workflow struct type"
  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          stages: [Stage.t()],
          intelligence: intelligence(),
          transitions: map() | nil,
          description: String.t() | nil
        }

  @enforce_keys [:id, :name, :stages]
  defstruct [
    :id,
    :name,
    :stages,
    intelligence: :dumb,
    transitions: nil,
    description: nil
  ]

  @doc """
  Creates a new workflow struct with the given attributes.

  Required fields: `:id`, `:name`, `:stages`
  Optional fields: `:intelligence` (default: `:dumb`), `:transitions`, `:description`

  ## Examples

      iex> Babysitter.Workflow.new("test", "Test Workflow", [])
      %Babysitter.Workflow{id: "test", name: "Test Workflow", stages: [], intelligence: :dumb}

      iex> Babysitter.Workflow.new("test", "Test", [], intelligence: :smart)
      %Babysitter.Workflow{id: "test", name: "Test", stages: [], intelligence: :smart}
  """
  @spec new(String.t(), String.t(), [Stage.t()], keyword()) :: t()
  def new(id, name, stages, opts \\ []) do
    %__MODULE__{
      id: id,
      name: name,
      stages: stages,
      intelligence: Keyword.get(opts, :intelligence, :dumb),
      transitions: Keyword.get(opts, :transitions),
      description: Keyword.get(opts, :description)
    }
  end
end
