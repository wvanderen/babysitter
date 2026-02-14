defmodule Babysitter.State.Repo.Migrations.CreateSessionStates do
  use Ecto.Migration

  def change do
    create table(:session_states, primary_key: false) do
      add(:id, :string, primary_key: true)
      add(:status, :string, default: "initializing", null: false)
      add(:tmux_name, :string)
      add(:started_at, :naive_datetime)
      add(:output_buffer, :text, default: "")
      add(:metadata, :map, default: "{}")
      add(:failure_reason, :string)
      add(:escalation_reason, :string)
      add(:validation_results, :map, default: "{}")
      add(:session_data, :map, default: "{}")

      timestamps()
    end

    create(index(:session_states, [:status]))
    create(index(:session_states, [:updated_at]))
  end
end
