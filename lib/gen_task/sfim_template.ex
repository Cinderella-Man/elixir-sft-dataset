defmodule GenTask.SfimTemplate do
  @moduledoc """
  The ONE source of the deterministic-sfim prompt text.

  Both the miner (`scripts/mint_sfim.exs`) and the drift gate
  (`scripts/resync_sfim_specs.exs`) build the prompt through this function, so
  a wording change lands in one place and the gate can re-derive every child
  prompt byte-exactly — template drift and spec drift are the same failure to
  it. Harmonized wording 2026-07-19 (Kamil-approved): the parenthetical says
  the attrs "belong directly above" the function rather than "shown above it
  in the module" — carved golds carry their `@doc`/`@spec` block since F24,
  so the skeleton no longer shows the attrs of the missing function.
  """

  @doc """
  The full prompt.md body for a deterministic sfim child.

  The register rotates by `unit_id` (`GenTask.Register`, docs/20). FROZEN
  across variants (numbered-namespace shape!): the H1 title
  `# Implement the missing function` as the FIRST line (format_corpus +
  resync_sfim sniff it), the exact `## The task` marker, the
  "## The module with `NAME` missing" heading (resync name recovery), the
  fence layout, and the `# TODO` blanks.
  """
  @spec prompt(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def prompt(name, spec, skeleton, unit_id) do
    render(
      GenTask.Register.variant(unit_id),
      name,
      String.trim(spec),
      String.trim_trailing(skeleton, "\n")
    )
  end

  defp render(0, name, spec, skeleton) do
    """
    # Implement the missing function

    Below is the complete specification of a task, followed by a working,
    fully tested module that solves it — except that `#{name}` has been
    removed: every clause body is blanked to `# TODO`. Implement exactly that
    function so the whole module passes the task's full test suite again.
    Change nothing else — every other function, attribute, and clause must
    stay exactly as shown.

    ## The task

    #{spec}

    ## The module with `#{name}` missing

    ```elixir
    #{skeleton}
    ```

    Give me only the complete implementation of `#{name}` (including any
    `@doc`/`@spec`/`@impl` lines that belong directly above it) — the
    function alone, not the whole module.
    """
  end

  defp render(1, name, spec, skeleton) do
    """
    # Implement the missing function

    Below you'll find a task's full specification, then a working, tested
    solution with one gap: `#{name}` — every clause body swapped for
    `# TODO`. Rebuild exactly that function so the module passes the task's
    whole suite again, and leave every other line precisely as shown.

    ## The task

    #{spec}

    ## The module with `#{name}` missing

    ```elixir
    #{skeleton}
    ```

    Reply with `#{name}` alone (bring along any `@doc`/`@spec`/`@impl` lines
    that belong directly above it) — just the function, never the whole
    module.
    """
  end

  defp render(2, name, spec, skeleton) do
    """
    # Implement the missing function

    The specification below is followed by its complete, tested solution —
    minus `#{name}`, whose clause bodies are all `# TODO`. Supply that one
    function; the rest of the module is fixed and must stay exactly as shown.

    ## The task

    #{spec}

    ## The module with `#{name}` missing

    ```elixir
    #{skeleton}
    ```

    Output only `#{name}` (with any `@doc`/`@spec`/`@impl` lines that belong
    directly above it) — the single function, not the module.
    """
  end
end
