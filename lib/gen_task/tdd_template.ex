defmodule GenTask.TddTemplate do
  @moduledoc """
  The ONE source of the TDD-inverse prompt text (docs/13 §2.8; same
  single-source policy as `GenTask.SfimTemplate`, 2026-07-19): the miner
  (`scripts/mint_tdd.exs`) and the drift gate (`scripts/resync_tdd_embeds.exs`)
  both build the prompt through this function, so template wording and the
  embedded harness share one byte-exact drift check.

  The shape is deliberately spec-free: the test suite IS the specification —
  the solver reads ExUnit tests and writes the module they pin. The parent's
  prose spec never appears; that information channel belongs to the `:single`
  shape.
  """

  @doc "The full prompt.md body for a TDD-inverse dir."
  @spec prompt(String.t()) :: String.t()
  def prompt(harness) do
    """
    # Make this test suite pass

    Below is a complete, self-contained ExUnit test suite. Treat it as the
    full specification: write the module (or modules) under test so that
    every test passes. Use only what the tests themselves require — the
    standard library and OTP unless the suite references anything else.
    Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
    the public API, no compiler warnings).

    ## The test suite

    ```elixir
    #{String.trim_trailing(harness, "\n")}
    ```

    Give me the complete implementation in a single file — the module(s)
    alone, not the tests.
    """
  end
end
