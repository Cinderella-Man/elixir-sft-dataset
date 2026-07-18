# Bring this working module up to house style

I asked for the following:

Write me an Elixir module called `Sanitizer` that not only cleans input but **reports every transformation it made** and supports a strict mode that *rejects* dirty input instead of silently fixing it.

Every function takes an options keyword list with a `:mode` of either `:lenient` (default) or `:strict`.

Common return contract for each function:
- If cleaning produced **no violations**: `{:ok, cleaned, []}` (in both modes).
- In `:lenient` mode **with** violations: `{:ok, cleaned, violations}` where `violations` is a list of atoms (in a fixed order, see below).
- In `:strict` mode **with** violations: `{:error, violations}`.
- A **hard failure** (empty result) always returns `{:error, [:empty]}` regardless of mode.

Functions:

- `Sanitizer.sql_identifier(input, opts \\ [])` — keep only `[A-Za-z0-9_]`. Violations, in order:
  - `:removed_illegal_chars` — if any character was stripped.
  - `:prefixed_digit_start` — if the cleaned value started with a digit and an underscore was prepended.
  - If the stripped value is empty → `{:error, [:empty]}`.

- `Sanitizer.filename(input, opts \\ [])` — strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to one, trim leading/trailing dots. Violations, in order:
  - `:removed_null_bytes` — if the input contained a null byte.
  - `:removed_path_separators` — if the input contained `/` or `\`.
  - `:removed_illegal_chars` — if any other disallowed characters were stripped.
  - `:collapsed_dots` — if a run of 2+ dots was collapsed.
  - `:trimmed_dots` — if leading/trailing dots were trimmed.
  - If the final value is empty → `{:error, [:empty]}`.

- `Sanitizer.text(input, opts \\ [])` — clean free text: strip C0 control characters (except `\t`, `\n`, `\r`), trim surrounding whitespace, then HTML-escape `&`, `<`, `>`, `"`, `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`. Violations, in order:
  - `:removed_control_chars` — if control characters were stripped.
  - `:trimmed_whitespace` — if trimming changed the value.
  - `:escaped_html` — if any character was HTML-escaped.
  - `text` never has a hard failure (an empty result is valid).

Give me the complete module in a single file, standard library only — no external dependencies.

Here is my implementation. It compiles and passes every test — the behavior
is correct — but it was rejected by the style review:

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

  # ── SQL identifier ─────────────────────────────────────────────────────────

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

  def filename(input, opts \\ []) when is_binary(input) do
    mode = Keyword.get(opts, :mode, :lenient)

    no_null = String.replace(input, "\0", "")
    no_sep = no_null |> String.replace("/", "") |> String.replace("\\", "")
    filtered = String.replace(no_sep, ~r/[^a-zA-Z0-9_\-.]/, "")
    collapsed = String.replace(filtered, ~r/\.{2,}/, ".")
    trimmed = String.trim(collapsed, ".")

    if trimmed == "" do
      {:error, [:empty]}
    else
      violations =
        []
        |> maybe(String.contains?(input, "\0"), :removed_null_bytes)
        |> maybe(
          String.contains?(input, "/") or String.contains?(input, "\\"),
          :removed_path_separators
        )
        |> maybe(filtered != no_sep, :removed_illegal_chars)
        |> maybe(collapsed != filtered, :collapsed_dots)
        |> maybe(trimmed != collapsed, :trimmed_dots)

      finalize(mode, trimmed, violations)
    end
  end

  # ── Free text ──────────────────────────────────────────────────────────────

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

  defp finalize(_mode, cleaned, []), do: {:ok, cleaned, []}
  defp finalize(:lenient, cleaned, violations), do: {:ok, cleaned, violations}
  defp finalize(:strict, _cleaned, violations), do: {:error, violations}

  defp maybe(list, true, v), do: list ++ [v]
  defp maybe(list, false, _v), do: list

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

The style review said:

```
The solution is green but does not meet the house style: no @spec on any public function; no @doc on any public function. Fix solution.ex so it has a `@moduledoc`, an `@spec` and `@doc` on public functions, no `TODO` markers, and compiles with ZERO warnings. Keep the behavior identical and do not weaken test_harness.exs.
```

Fix every finding in the review WITHOUT changing any behavior: the module
must keep passing exactly the tests it passes now. Give me the complete
corrected module in a single file.
<!-- minted from logs/attempts/096_004_reporting_sanitizer_with_strict_and_lenient_modes_01/attempt_0 -->
