defmodule GenTask.Register do
  @moduledoc """
  Deterministic prompt-register selection for the templated shapes (G3,
  docs/20-register-rotation-design.md).

  Every templated `prompt.md` is rendered by its shape's builder from one of a
  small set of PROSE variants; the variant is chosen by hashing the unit's dir
  basename, so the same unit always renders the same bytes — resyncs reproduce
  prompts exactly, and the corpus's boilerplate register stops being monotone.

  What may vary between variants and what is FROZEN (title lines, parsed
  headings, recovery sentences, fence layouts, `# TODO` markers, the S9
  timer-vocabulary ban) is inventoried in docs/20 §2 — verified against every
  parser that reads prompt text. `test/gen_task/register_test.exs` asserts the
  frozen anchors variant-by-variant.

  `:erlang.phash2/2` is documented as portable and stable across OTP releases
  (unlike `phash/2`), and the toolchain is pinned besides.
  """

  @n_variants 3

  @doc "Number of register variants every templated shape provides."
  @spec n_variants() :: pos_integer()
  def n_variants, do: @n_variants

  @doc """
  The register variant for a unit: `phash2(basename(unit_id), n_variants())`.

  Accepts a dir basename or any path ending in it — only the basename hashes,
  so mint-time ids and resync-time paths agree.
  """
  @spec variant(String.t()) :: non_neg_integer()
  def variant(unit_id) when is_binary(unit_id) do
    :erlang.phash2(Path.basename(unit_id), @n_variants)
  end
end
