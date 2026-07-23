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

  @doc """
  The full prompt.md body for a spec-FIM dir.

  The register rotates by `unit_id` (`GenTask.Register`, docs/20). FROZEN
  across variants: the recovery SENTENCE — `the `@spec` for` at line end
  followed by the backticked `name/arity` at the next line start, then
  ` has been removed` (the resync regex allows only an optional newline
  between "for" and the backtick — a space breaks recovery) — plus the
  "## The module with the `@spec` for `name/arity` missing" heading, the
  fence layout, and the `# TODO: @spec` marker.
  """
  @spec prompt(String.t(), pos_integer(), String.t(), String.t()) :: String.t()
  def prompt(name, arity, skeleton, unit_id) do
    render(
      GenTask.Register.variant(unit_id),
      name,
      arity,
      String.trim_trailing(skeleton, "\n")
    )
  end

  defp render(0, name, arity, skeleton) do
    """
    # Write the missing @spec

    Below is a complete, working module — except that the `@spec` for
    `#{name}/#{arity}` has been removed; its place is marked `# TODO: @spec`.
    Write exactly that typespec: one `@spec` attribute for `#{name}/#{arity}`,
    consistent with the function's arguments, guards, and every return shape
    the implementation can produce. Change nothing else.

    ## The module with the `@spec` for `#{name}/#{arity}` missing

    ```elixir
    #{skeleton}
    ```

    Give me only the `@spec` attribute — the attribute alone (however many
    lines it spans), not the whole module.
    """
  end

  defp render(1, name, arity, skeleton) do
    """
    # Reconstruct the missing typespec

    In the otherwise-complete module below, the `@spec` for
    `#{name}/#{arity}` has been removed; `# TODO: @spec` holds its place.
    Write that one attribute — a `@spec` for `#{name}/#{arity}` faithful to
    the arguments, guards, and every return shape the code can actually
    produce. Nothing else changes.

    ## The module with the `@spec` for `#{name}/#{arity}` missing

    ```elixir
    #{skeleton}
    ```

    Reply with the `@spec` attribute alone, however many lines it needs —
    not the module.
    """
  end

  defp render(2, name, arity, skeleton) do
    """
    # Fill in one @spec

    Below: a working module where the `@spec` for
    `#{name}/#{arity}` has been removed (see the `# TODO: @spec` marker).
    Provide exactly that typespec, consistent with the implementation's
    arguments, guards, and all reachable return shapes. No other edits.

    ## The module with the `@spec` for `#{name}/#{arity}` missing

    ```elixir
    #{skeleton}
    ```

    The `@spec` attribute only — nothing more.
    """
  end
end
