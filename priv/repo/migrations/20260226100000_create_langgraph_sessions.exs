defmodule Babysitter.State.Repo.Migrations.CreateLangGraphSessions do
  use Ecto.Migration

  def change do
    create table(:langgraph_sessions, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:session_id, :string, null: false)
      add(:thread_id, :string, null: false)
      add(:checkpoint_id, :string)

      timestamps()
    end

    create(unique_index(:langgraph_sessions, [:session_id]))
    create(index(:langgraph_sessions, [:thread_id]))
  end
end
