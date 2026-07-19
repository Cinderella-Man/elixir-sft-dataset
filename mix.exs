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
      deps: deps(),
      # T1.6: golds legitimately call ExUnit helpers (074_003's assertion
      # helpers use ExUnit.Assertions.flunk/1); without :ex_unit in the PLT
      # those calls read as unknown functions.
      dialyzer: [plt_add_apps: [:ex_unit]]
    ]
  end

  def application do
    [
      # :dialyzer — GenTask.Dialyzer calls the OTP app directly; without listing
      # it the compiler warns "module :dialyzer is not available" on fresh CI
      # builds (2026-07-19).
      extra_applications: [:logger, :crypto, :dialyzer],
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
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Spec verification over the gold solutions (T1.6, docs/13 §2.6):
      # one-time PLT + scripts/dialyzer_golds.exs driver + weekly CI gate.
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
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
