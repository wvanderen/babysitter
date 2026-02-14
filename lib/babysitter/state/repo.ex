defmodule Babysitter.State.Repo do
  use Ecto.Repo,
    otp_app: :babysitter,
    adapter: Ecto.Adapters.SQLite3

  @doc """
  Returns the database path for session state.
  """
  def db_path do
    Application.get_env(:babysitter, Babysitter.State.Repo, [])
    |> Keyword.get(:database, "session_state.db")
  end
end
