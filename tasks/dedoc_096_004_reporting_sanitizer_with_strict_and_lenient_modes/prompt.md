# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Sanitizer do
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
