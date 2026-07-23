# Debug and repair this module

A colleague shipped the module below for the task described next, and one
behavior bug made it through review. The test suite (not shown here)
produces the failure report at the bottom. Track the bug down and repair
it — keep the diff minimal and leave working code exactly as it is. Reply
with the complete corrected module.

## What the module is supposed to do

Implement `Sanitizer` — an Elixir module that cleans input, reports every transformation it made, and supports a strict mode that rejects dirty input instead of silently fixing it.

**Options**
- Every function takes an options keyword list as its final argument.
- The keyword list carries a `:mode` key of either `:lenient` (the default) or `:strict`.

**Common return contract (all functions)**
- Cleaning produced no violations: `{:ok, cleaned, []}` — in both modes.
- `:lenient` mode with violations: `{:ok, cleaned, violations}`, where `violations` is a list of atoms in the fixed order specified per function below.
- `:strict` mode with violations: `{:error, violations}`.
- Hard failure (empty result): always `{:error, [:empty]}`, regardless of mode.

**`Sanitizer.sql_identifier(input, opts \\ [])`**
- Keep only `[A-Za-z0-9_]`.
- Violations, in this order:
  - `:removed_illegal_chars` — any character was stripped.
  - `:prefixed_digit_start` — the cleaned value started with a digit and an underscore was prepended.
- Stripped value is empty → `{:error, [:empty]}`.

**`Sanitizer.filename(input, opts \\ [])`**
- Strip null bytes; strip `/` and `\`; keep only `[A-Za-z0-9_.-]`; collapse runs of 2+ dots to one; trim leading/trailing dots.
- Violations, in this order:
  - `:removed_null_bytes` — the input contained a null byte.
  - `:removed_path_separators` — the input contained `/` or `\`.
  - `:removed_illegal_chars` — any other disallowed characters were stripped.
  - `:collapsed_dots` — a run of 2+ dots was collapsed.
  - `:trimmed_dots` — leading/trailing dots were trimmed.
- Final value is empty → `{:error, [:empty]}`.

**`Sanitizer.text(input, opts \\ [])`**
- Clean free text: strip C0 control characters except `\t`, `\n`, `\r`; trim surrounding whitespace; then HTML-escape `&`, `<`, `>`, `"`, `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&#39;`. Escape `&` first so the introduced entities are not re-escaped.
- Violations, in this order:
  - `:removed_control_chars` — control characters were stripped.
  - `:trimmed_whitespace` — trimming changed the value.
  - `:escaped_html` — any character was HTML-escaped.
- `text` never has a hard failure; an empty result is valid.

**Deliverable**
- Complete module in a single file.
- Standard library only — no external dependencies.

## The buggy module

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
  defp finalize(:lenient, cleaned, violations), do: {:error, cleaned, violations}
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

## Failing test report

```
10 of 18 test(s) failed:

  * test sql_identifier/2 lenient reports removed illegal chars
      
      
      match (=) failed
      code:  assert {:ok, "users", [:removed_illegal_chars]} = Sanitizer.sql_identifier("us;ers")
      left:  {:ok, "users", [:removed_illegal_chars]}
      right: {:error, "users", [:removed_illegal_chars]}
      

  * test sql_identifier/2 lenient reports digit-start prefixing
      
      
      match (=) failed
      code:  assert {:ok, "_1table", [:prefixed_digit_start]} = Sanitizer.sql_identifier("1table")
      left:  {:ok, "_1table", [:prefixed_digit_start]}
      right: {:error, "_1table", [:prefixed_digit_start]}
      

  * test sql_identifier/2 violations come in fixed order
      
      
      match (=) failed
      code:  assert {:ok, "_1a", [:removed_illegal_chars, :prefixed_digit_start]} = Sanitizer.sql_identifier("1;a")
      left:  {:ok, "_1a", [:removed_illegal_chars, :prefixed_digit_start]}
      right: {:error, "_1a", [:removed_illegal_chars, :prefixed_digit_start]}
      

  * test filename/2 reports null bytes
      
      
      match (=) failed
      code:  assert {:ok, "file.txt", [:removed_null_bytes]} = Sanitizer.filename("file\0.txt")
      left:  {:ok, "file.txt", [:removed_null_bytes]}
      right: {:error, "file.txt", [:removed_null_bytes]}
      

  (…6 more)
```
