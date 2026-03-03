defmodule GswarmMcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :gswarm_mcp,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {GswarmMcp.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tidewave, "~> 0.5"},
      {:plug_cowboy, "~> 2.6"},
      {:jason, "~> 1.4"}
    ]
  end
end
