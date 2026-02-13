defmodule BabysitterWeb.ChannelCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest

      @endpoint BabysitterWeb.Endpoint
    end
  end

  setup _context do
    :ok
  end
end
