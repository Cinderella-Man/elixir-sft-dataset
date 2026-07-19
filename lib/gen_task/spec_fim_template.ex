defmodule GenTask.SpecFimTemplate do
  @moduledoc """
  The ONE source of the spec-FIM prompt text (docs/13 §2.8; single-source
  policy per SfimTemplate/TddTemplate, 2026-07-19): the miner
  (`scripts/mint_specfim.exs`) and the drift gate
  (`scripts/resync_specfim_embeds.exs`) both build prompts through this
  function.

  The shape: a complete working module with exactly one `@spec` attribute
  removed, its place held by the `# TODO: @spec` marker; the completion is
  that attribute alone. Spec TRUTH for the gold is inherited — the parent's
  dialyzer gate already verified the identical bytes in context.
  """

  @doc "The `# TODO: @spec` marker line content (trimmed; miners indent it)."
  @spec marker() :: String.t()
  def marker, do: "# TODO: @spec"

  @doc "The full prompt.md body for a spec-FIM dir."
  @spec prompt(String.t(), pos_integer(), String.t()) :: String.t()
  def prompt(name, arity, skeleton) do
    """
    # Write the missing @spec

    Below is a complete, working module — except that the `@spec` for
    `#{name}/#{arity}` has been removed; its place is marked `# TODO: @spec`.
    Write exactly that typespec: one `@spec` attribute for `#{name}/#{arity}`,
    consistent with the function's arguments, guards, and every return shape
    the implementation can produce. Change nothing else.

    ## The module with the `@spec` for `#{name}/#{arity}` missing

    ```elixir
    #{String.trim_trailing(skeleton, "\n")}
    ```

    Give me only the `@spec` attribute — the attribute alone (however many
    lines it spans), not the whole module.
    """
  end
end
