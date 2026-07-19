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

  @doc "The full prompt.md body for a deterministic sfim child."
  @spec prompt(String.t(), String.t(), String.t()) :: String.t()
  def prompt(name, spec, skeleton) do
    """
    # Implement the missing function

    Below is the complete specification of a task, followed by a working,
    fully tested module that solves it — except that `#{name}` has been
    removed: every clause body is blanked to `# TODO`. Implement exactly that
    function so the whole module passes the task's full test suite again.
    Change nothing else — every other function, attribute, and clause must
    stay exactly as shown.

    ## The task

    #{String.trim(spec)}

    ## The module with `#{name}` missing

    ```elixir
    #{String.trim_trailing(skeleton, "\n")}
    ```

    Give me only the complete implementation of `#{name}` (including any
    `@doc`/`@spec`/`@impl` lines that belong directly above it) — the
    function alone, not the whole module.
    """
  end
end
