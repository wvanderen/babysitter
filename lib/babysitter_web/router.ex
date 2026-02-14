defmodule BabysitterWeb.Router do
  use Phoenix.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:protect_from_forgery)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/api", BabysitterWeb do
    pipe_through(:api)

    resources("/sessions", SessionController, only: [:index, :show, :create, :delete])
    post("/sessions/:id/pause", SessionController, :pause)
    post("/sessions/:id/resume", SessionController, :resume)
    post("/sessions/:id/intervene", SessionController, :intervene)

    resources "/workflows", WorkflowController, only: [:index, :show, :create] do
      post("/execute", WorkflowController, :execute)
    end
  end
end
