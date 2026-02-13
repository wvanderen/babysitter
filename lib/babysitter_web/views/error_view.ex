defmodule BabysitterWeb.ErrorView do
  use Phoenix.Component

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  def render("404.json", _assigns) do
    %{error: "Not Found"}
  end

  def render("500.json", _assigns) do
    %{error: "Internal Server Error"}
  end
end
