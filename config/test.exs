import Config

config :babysitter, BabysitterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test_secret_key_base_for_babysitter_application_do_not_use_in_prod",
  server: false

config :logger, level: :warning
