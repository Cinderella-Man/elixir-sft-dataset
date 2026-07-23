# Write tests for this module

Below is a completed Elixir module and the original specification it was built to
satisfy. Write a comprehensive ExUnit test harness that verifies a correct
implementation of this module.

Requirements for the harness:
- Define a module `<Module>Test` that does `use ExUnit.Case, async: false`.
- Do NOT call `ExUnit.start()` — the evaluator starts ExUnit itself.
- Make it self-contained: any fakes, clock Agents, or helpers are defined inline.
- Cover the full public API and the important edge cases described in the spec.
- It must compile with ZERO warnings (prefix unused variables with `_`; match float
  zero as `+0.0`/`-0.0`).
- Give me the complete harness in a single file.

## Original specification

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

- `Sanitizer.text(input, opts \\ [])` — clean free text: strip C0 control characters (except `\t`, `\n`, `\r`), trim surrounding whitespace, then HTML-escape `&`, `<`, `>`, `"`, `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;` (escape `&` first so the entities you introduce are not re-escaped). Violations, in order:
  - `:removed_control_chars` — if control characters were stripped.
  - `:trimmed_whitespace` — if trimming changed the value.
  - `:escaped_html` — if any character was HTML-escaped.
  - `text` never has a hard failure (an empty result is valid).

Give me the complete module in a single file, standard library only — no external dependencies.

## Module under test

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
