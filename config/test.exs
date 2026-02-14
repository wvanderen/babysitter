import Config

config :babysitter, BabysitterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_for_babysitter_application_do_not_use_in_prod",
  server: false

config :babysitter, Babysitter.TD.Repo,
  database: ".todos/test_issues.db",
  pool_size: 5

config :babysitter, Babysitter.State.Repo,
  database: ".todos/test_session_states.db",
  pool_size: 5

config :logger, level: :warning
