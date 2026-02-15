defmodule BabysitterWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :babysitter

  @static_paths ~w(assets fonts images favicon.ico robots.txt)

  socket("/socket", BabysitterWeb.UserSocket, websocket: [timeout: 45_000])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Jason
  )

  plug(Plug.Static,
    at: "/",
    from: :babysitter,
    gzip: false,
    only: @static_paths
  )

  plug(Plug.Session,
    store: :cookie,
    key: "_babysitter_key",
    signing_salt: "babysitter_secret",
    same_site: "Lax"
  )

  plug(BabysitterWeb.Router)

  def static_paths, do: @static_paths
end
