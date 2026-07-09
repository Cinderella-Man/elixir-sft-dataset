# Fill in the middle: `Sanitizer.sql_identifier/2`

Implement the public `sql_identifier/2` function. It sanitizes `input` into a SQL
identifier by keeping only the characters `[A-Za-z0-9_]` (stripping everything
else via `String.replace/3` with a regex). It reads the `:mode` from `opts`
(defaulting to `:lenient`).

Behavior:

- If the stripped value is empty, return `{:error, [:empty]}` (a hard failure,
  regardless of mode).
- Otherwise build the violation list in this fixed order:
  - `:removed_illegal_chars` — include it only if the stripped value differs from
    the original `input` (i.e. some character was removed).
  - `:prefixed_digit_start` — if the stripped value starts with a digit, prepend
    an underscore (`"_" <> stripped`) to form the cleaned value and include this
    violation; otherwise the cleaned value is the stripped value and this
    violation is omitted.
- Return the result by delegating to the private `finalize/3` helper with the
  mode, the cleaned value, and the ordered violations list. `finalize/3` produces
  `{:ok, cleaned, []}` when there are no violations, `{:ok, cleaned, violations}`
  in `:lenient` mode, and `{:error, violations}` in `:strict` mode.

The function has a guard `when is_binary(input)`.

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
    # TODO
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