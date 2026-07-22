Implement the public `filename/2` function. It sanitizes `input` into a safe
filename and reports every transformation it made, honoring the module's
`:mode` contract (`:lenient` default vs `:strict`).

Read `mode` from `opts` (default `:lenient`). Then clean the input through these
steps, in order:

1. Strip all null bytes (`"\0"`).
2. Strip path separators — both `/` and `\`.
3. Keep only `[A-Za-z0-9_.-]`, stripping any other disallowed characters.
4. Collapse any run of 2+ dots into a single dot.
5. Trim leading and trailing dots.

If the final value is empty, return `{:error, [:empty]}` regardless of mode.

Otherwise build the violations list, in this fixed order, adding each atom only
when that transformation actually applied to `input`:

- `:removed_null_bytes` — the input contained a null byte.
- `:removed_path_separators` — the input contained `/` or `\`.
- `:removed_illegal_chars` — other disallowed characters were stripped.
- `:collapsed_dots` — a run of 2+ dots was collapsed.
- `:trimmed_dots` — leading/trailing dots were trimmed.

Use the `maybe/3` helper to conditionally append each violation, and hand the
cleaned value plus violations to `finalize/3` so the mode-specific return
contract is applied.

```elixir
defmodule Sanitizer do
  @moduledoc """
  Reporting sanitizer with `:lenient` (default) and `:strict` modes.

  Each function returns a violation report describing what it changed:

    * no violations → `{:ok, cleaned, []}` (both modes)
    * `:lenient` with violations → `{:ok, cleaned, violations}`
    * `:strict` with violations → `{:error, violations}`
    * hard failure (empty result) → `{:error, [:empty]}`

  Standard library only — no external dependencies.
  """

  @type result :: {:ok, String.t(), [atom()]} | {:error, [atom()]}

  # ── SQL identifier ─────────────────────────────────────────────────────────

  @doc """
  Sanitizes `input` into a SQL identifier, keeping only `[A-Za-z0-9_]`.

  Reports `:removed_illegal_chars` when characters were stripped and
  `:prefixed_digit_start` when a leading underscore was prepended because the
  value started with a digit. An empty stripped value is `{:error, [:empty]}`.
  """
  @spec sql_identifier(String.t(), keyword()) :: result()
  def sql_identifier(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)
    stripped = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    if stripped == "" do
      {:error, [:empty]}
    else
      removed = if stripped != input, do: [:removed_illegal_chars], else: []

      {cleaned, prefixed} =
        if String.match?(stripped, ~r/\A[0-9]/) do
          {"_" <> stripped, [:prefixed_digit_start]}
        else
          {stripped, []}
        end

      finalize(mode, cleaned, removed ++ prefixed)
    end
  end

  # ── Filename ───────────────────────────────────────────────────────────────

  @doc """
  Sanitizes `input` into a safe filename.

  Strips null bytes and path separators, keeps only `[A-Za-z0-9_.-]`, collapses
  runs of 2+ dots to one, and trims leading/trailing dots. Reports each of these
  transformations in fixed order. An empty final value is `{:error, [:empty]}`.
  """
  @spec filename(String.t(), keyword()) :: result()
  def filename(input, opts \\ []) when is_binary(input) do
    # TODO
  end

  # ── Free text ──────────────────────────────────────────────────────────────

  @doc """
  Sanitizes free `text`.

  Strips C0 control characters (except `\\t`, `\\n`, `\\r`), trims surrounding
  whitespace, then HTML-escapes `&`, `<`, `>`, `"`, `'`. Reports each of these
  transformations in fixed order. An empty result is valid (no hard failure).
  """
  @spec text(String.t(), keyword()) :: result()
  def text(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_ctrl = String.replace(input, ~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    trimmed = String.trim(no_ctrl)
    escaped = html_escape(trimmed)

    violations =
      []
      |> maybe(no_ctrl != input, :removed_control_chars)
      |> maybe(trimmed != no_ctrl, :trimmed_whitespace)
      |> maybe(escaped != trimmed, :escaped_html)

    finalize(mode, escaped, violations)
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  @spec finalize(:lenient | :strict, String.t(), [atom()]) :: result()
  defp finalize(_mode, cleaned, []), do: {:ok, cleaned, []}
  defp finalize(:lenient, cleaned, violations), do: {:ok, cleaned, violations}
  defp finalize(:strict, _cleaned, violations), do: {:error, violations}

  @spec maybe([atom()], boolean(), atom()) :: [atom()]
  defp maybe(list, true, v), do: list ++ [v]
  defp maybe(list, false, _v), do: list

  @spec html_escape(String.t()) :: String.t()
  defp html_escape(s) do
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
```