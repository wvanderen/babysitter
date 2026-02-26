defmodule Babysitter.State.LangGraphSession do
  @moduledoc """
  Schema for persisting LangGraph session→thread mapping for recovery.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "langgraph_sessions" do
    field(:session_id, :string)
    field(:thread_id, :string)
    field(:checkpoint_id, :string)

    timestamps()
  end

  @type t :: %__MODULE__{
          id: String.t(),
          session_id: String.t(),
          thread_id: String.t(),
          checkpoint_id: String.t() | nil,
          inserted_at: NaiveDateTime.t(),
          updated_at: NaiveDateTime.t()
        }
end
