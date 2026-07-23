defmodule GenTask.BundleFimTemplate do
  @moduledoc """
  The ONE source of the bundle-FIM prompt text (docs/13 §2.8 "file-level
  bundle FIM"; single-source policy per the other 2026-07-19 templates): the
  miner (`scripts/mint_bundlefim.exs`) and the drift gate
  (`scripts/resync_bundlefim_embeds.exs`) both build prompts through this
  function.

  The shape: a multi-file bundle solution with ONE file's entire content
  blanked to `# TODO`; the completion is that file alone (the
  migration/schema/router/controller the bundle is missing). Units keep the
  `_0N`/:fim shape — `Runner.run_fim_bundle`/`reconstruct_bundle` already
  grade whole-file candidates against the parent harness.
  """

  @doc """
  The full prompt.md body for a bundle-FIM child.

  The register rotates by `unit_id` (`GenTask.Register`, docs/20). FROZEN
  across variants (numbered-namespace shape!): the H1 title
  `# Implement the missing file` as the FIRST line (format_corpus +
  resync_bundlefim sniff it), the exact `## The task` marker, the
  "## The bundle with `PATH` missing" heading (resync path recovery), the
  fence layout, and the `# TODO` blank.
  """
  @spec prompt(String.t(), String.t(), String.t(), String.t()) :: String.t()
  def prompt(path, spec, skeleton, unit_id) do
    render(
      GenTask.Register.variant(unit_id),
      path,
      String.trim(spec),
      String.trim_trailing(skeleton, "\n")
    )
  end

  defp render(0, path, spec, skeleton) do
    """
    # Implement the missing file

    Below is the complete specification of a task, followed by its working,
    fully tested multi-file solution — except that the entire content of
    `#{path}` has been blanked to `# TODO`. Write that file so the whole
    bundle passes the task's full test suite again. Change nothing else —
    every other file must stay exactly as shown.

    ## The task

    #{spec}

    ## The bundle with `#{path}` missing

    ```elixir
    #{skeleton}
    ```

    Give me only the complete content of `#{path}` — that one file, nothing
    else.
    """
  end

  defp render(1, path, spec, skeleton) do
    """
    # Implement the missing file

    A task's specification is followed by its working multi-file solution —
    with one casualty: the entire content of `#{path}` is now `# TODO`.
    Write that file so the whole bundle passes the task's suite again; every
    other file stays exactly as printed.

    ## The task

    #{spec}

    ## The bundle with `#{path}` missing

    ```elixir
    #{skeleton}
    ```

    Reply with the complete content of `#{path}` and nothing else.
    """
  end

  defp render(2, path, spec, skeleton) do
    """
    # Implement the missing file

    Below: the task, then its tested multi-file solution in which the whole
    of `#{path}` has been blanked to `# TODO`. Reconstruct that single file;
    the remaining files are fixed and must stay exactly as shown.

    ## The task

    #{spec}

    ## The bundle with `#{path}` missing

    ```elixir
    #{skeleton}
    ```

    Output only `#{path}`'s full content — one file, nothing besides.
    """
  end
end
