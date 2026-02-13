import Config

config :babysitter, BabysitterWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev_secret_key_base_for_babysitter_application_do_not_use_in_prod"

config :logger, level: :debug
