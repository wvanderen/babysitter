defmodule Babysitter.MixProject do
  use Mix.Project

  def project do
    [
      app: :babysitter,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Babysitter.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:plug_cowboy, "~> 2.7"},
      {:ecto_sqlite3, "~> 0.17"},
      {:yamerl, "~> 0.10"},
      {:tesla, "~> 1.13"},
      {:finch, "~> 0.19"}
    ]
  end
end
