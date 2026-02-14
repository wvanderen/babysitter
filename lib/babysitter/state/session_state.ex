defmodule Babysitter.State.SessionState do
  @moduledoc """
  Schema for persisting session state to SQLite for recovery.
  """

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "session_states" do
    field(:status, :string, default: "initializing")
    field(:tmux_name, :string)
    field(:started_at, :naive_datetime)
    field(:output_buffer, :string, default: "")
    field(:metadata, :map, default: %{})
    field(:failure_reason, :string)
    field(:escalation_reason, :string)
    field(:validation_results, :map, default: %{})
    field(:session_data, :map, default: %{})

    timestamps()
  end

  @type t :: %__MODULE__{
          id: String.t(),
          status: String.t(),
          tmux_name: String.t() | nil,
          started_at: NaiveDateTime.t() | nil,
          output_buffer: String.t(),
          metadata: map(),
          failure_reason: String.t() | nil,
          escalation_reason: String.t() | nil,
          validation_results: map(),
          session_data: map()
        }
end
