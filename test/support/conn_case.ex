ExUnit.start()

defmodule BabysitterWeb.ConnCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest

      @endpoint BabysitterWeb.Endpoint
    end
  end
end
