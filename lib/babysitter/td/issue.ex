defmodule Babysitter.TD.Issue do
  @moduledoc """
  Schema for TD issues stored in SQLite.
  """
  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "issues" do
    field(:title, :string)
    field(:description, :string, default: "")
    field(:status, :string, default: "open")
    field(:type, :string, default: "task")
    field(:priority, :string, default: "P2")
    field(:points, :integer, default: 0)
    field(:labels, :string, default: "")
    field(:parent_id, :string, default: "")
    field(:acceptance, :string, default: "")
    field(:implementer_session, :string, default: "")
    field(:reviewer_session, :string, default: "")
    field(:minor, :integer, default: 0)
    field(:created_branch, :string, default: "")
    field(:creator_session, :string, default: "")
    field(:sprint, :string, default: "")

    field(:created_at, :naive_datetime)
    field(:updated_at, :naive_datetime)
  end

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          description: String.t(),
          status: String.t(),
          type: String.t(),
          priority: String.t(),
          points: integer(),
          labels: String.t(),
          parent_id: String.t(),
          acceptance: String.t(),
          implementer_session: String.t(),
          reviewer_session: String.t()
        }
end
