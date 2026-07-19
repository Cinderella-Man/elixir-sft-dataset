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

  @doc "The full prompt.md body for a bundle-FIM child."
  @spec prompt(String.t(), String.t(), String.t()) :: String.t()
  def prompt(path, spec, skeleton) do
    """
    # Implement the missing file

    Below is the complete specification of a task, followed by its working,
    fully tested multi-file solution — except that the entire content of
    `#{path}` has been blanked to `# TODO`. Write that file so the whole
    bundle passes the task's full test suite again. Change nothing else —
    every other file must stay exactly as shown.

    ## The task

    #{String.trim(spec)}

    ## The bundle with `#{path}` missing

    ```elixir
    #{String.trim_trailing(skeleton, "\n")}
    ```

    Give me only the complete content of `#{path}` — that one file, nothing
    else.
    """
  end
end
