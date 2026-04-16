defmodule ElixirBenchmark.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_benchmark,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ElixirBenchmark.Application, []}
    ]
  end

  # Include test/support in the compilation path during tests
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Database (for Ecto/Phoenix tasks)
      {:ecto_sql, "~> 3.11"},
      {:postgrex, "~> 0.18"},
      {:ecto_sqlite3, "~> 0.17"},

      # Web (for Phoenix/Plug tasks)
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},

      # HTTP client (for client-side tasks)
      {:req, "~> 0.5"},

      # Data processing (for Explorer/Nx tasks)
      {:explorer, "~> 0.9"},
      {:nx, "~> 0.9"},

      # CSV parsing
      {:nimble_csv, "~> 1.2"},

      # Testing
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:mox, "~> 1.1", only: :test},

      # Decimal arithmetic
      {:decimal, "~> 2.1"},

      # Static analysis (for scoring solutions)
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
