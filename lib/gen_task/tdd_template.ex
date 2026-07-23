defmodule GenTask.TddTemplate do
  @moduledoc """
  The prompt template for TDD-inverse (`tdd_`) dirs — single source for the
  miner (`scripts/mint_tdd.exs`) and the resync gate
  (`scripts/resync_tdd_embeds.exs`).

  The framing is deliberately minimal: the harness IS the specification, and
  the solver reads ExUnit tests and writes the module they pin. The parent's
  prose spec never appears; that information channel belongs to the `:single`
  shape.

  The register rotates by `unit_id` (`GenTask.Register`, docs/20). FROZEN
  across variants: the `## The test suite` heading, the fence layout, and the
  timer-vocabulary ban (a tdd prompt has no contract_text marker, so the WHOLE
  prompt is contract scope).
  """

  alias GenTask.Register

  @doc "The full prompt.md body for a TDD-inverse dir."
  @spec prompt(String.t(), String.t()) :: String.t()
  def prompt(harness, unit_id) do
    render(Register.variant(unit_id), String.trim_trailing(harness, "\n"))
  end

  defp render(0, harness) do
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
    #{harness}
    ```

    Give me the complete implementation in a single file — the module(s)
    alone, not the tests.
    """
  end

  defp render(1, harness) do
    """
    # The tests are the spec

    Below is a complete, self-contained ExUnit suite. It is the only
    specification you get: build the module (or modules) it exercises until
    every test passes. Reach for nothing beyond what the tests themselves
    require — the standard library and OTP unless the suite says otherwise.
    House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
    no compiler warnings).

    ## The test suite

    ```elixir
    #{harness}
    ```

    Send back the implementation only — one file, no tests.
    """
  end

  defp render(2, harness) do
    """
    # Implement to green

    Treat the ExUnit suite below as the full requirements document. Write the
    code under test so the whole suite passes. Dependencies: only what the
    tests already use (the standard library and OTP otherwise). Style:
    `@moduledoc`, `@doc` + `@spec` on the public API, warning-free compile.

    ## The test suite

    ```elixir
    #{harness}
    ```

    Deliverable: the module(s) alone in a single file — not the tests.
    """
  end
end
