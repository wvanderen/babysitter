defmodule Babysitter.TD.Repo do
  use Ecto.Repo,
    otp_app: :babysitter,
    adapter: Ecto.Adapters.SQLite3
end
