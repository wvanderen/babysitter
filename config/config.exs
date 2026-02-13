import Config

config :babysitter, BabysitterWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: BabysitterWeb.ErrorView, accepts: ~w(json)],
  pubsub_server: Babysitter.PubSub,
  live_view: [signing_salt: "babysitter_live_secret"]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
