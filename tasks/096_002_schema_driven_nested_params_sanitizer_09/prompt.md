# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `html_escape` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Ticket: `Sanitizer` — schema-driven nested params sanitizer

**Summary:** Implement an Elixir module `Sanitizer` that sanitizes nested parameter maps against a declarative schema (mass-assignment protection plus per-field cleaning for controller params). Single file, standard library only, no external dependencies.

**Entry point**

- `Sanitizer.sanitize(params, schema)` is the core function.
- `params` is a possibly deeply nested map with **string keys**.
- `schema` describes how to treat each key; it is itself a map with string keys.
- Each schema value is a "field spec": an atom field type, a `{:list, inner}` tuple, or a nested schema map.

**Field spec — atom field types**

- `:text` — HTML-escape the value and clean it. Strip C0 control characters except tab `\t`, newline `\n`, carriage return `\r`; trim surrounding whitespace; then escape `&`, `<`, `>`, `"`, and `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, and `&#39;` respectively. Always succeeds for binaries. Non-binary → error `:not_a_string`.
- `:identifier` — safe SQL identifier. Keep only `[A-Za-z0-9_]`. Empty after stripping → error `:empty`. If the result starts with a digit, prepend `_`. Non-binary → `:not_a_string`.
- `:filename` — safe filename. Strip null bytes; strip `/` and `\`; keep only `[A-Za-z0-9_.-]`; collapse runs of 2+ dots to a single dot; trim leading/trailing dots. Empty result → `:empty`. Non-binary → `:not_a_string`.
- `:integer` — accept an integer as-is; accept a binary that parses cleanly to an integer after trimming; otherwise error `:not_an_integer`.
- `:boolean` — accept `true`/`false`, or the strings `"true"`/`"false"`; otherwise error `:not_a_boolean`.

**Field spec — composite types**

- `{:list, inner}` — value must be a list; apply `inner` (itself a field spec) to every element.
- Nested schema map — value must be a map; recurse.

**Key selection**

- Whitelist semantics: only keys present in the schema survive into the output. Any key in `params` not in the schema is dropped.
- Missing keys: a schema key with no corresponding key in `params` is skipped — not an error, not present in output.

**Error reporting**

- Collect *all* field errors, keyed by **path**: a list of segments made of string keys and integer list indices, e.g. `["profile", "handle"]` or `["scores", 1]`.
- No errors → return `{:ok, cleaned_map}`.
- At least one error → return `{:error, errors_map}`, where `errors_map` maps each failing path to its reason atom.

**Type-shape mismatches**

- Nested schema map expected but value is not a map → `:expected_map` at that field's path.
- `{:list, inner}` spec given a non-list value → `:expected_list`.
- `sanitize(%{"profile" => "nope"}, %{"profile" => %{"bio" => :text}})` returns `{:error, %{["profile"] => :expected_map}}`.
- `sanitize(%{"tags" => "nope"}, %{"tags" => {:list, :text}})` returns `{:error, %{["tags"] => :expected_list}}`.

**Public helpers**

- Expose `Sanitizer.sql_identifier/1` and `Sanitizer.filename/1`, each returning `{:ok, string}` or `{:error, :empty}`.

**Deliverable**

- The complete module in a single file.

## The module with `html_escape` missing

```elixir
defmodule Sanitizer do
  @moduledoc """
  Schema-driven sanitizer for nested parameter maps.

  `sanitize/2` walks a nested `params` map (string keys) against a declarative
  `schema`, applying per-field cleaning, dropping keys not present in the
  schema (whitelist / mass-assignment protection), and collecting all field
  errors keyed by their path.

  All logic is pure — standard library only, no external dependencies.
  """

  @type field :: atom() | {:list, field()} | map()

  @doc """
  Sanitize `params` against `schema`.

  Returns `{:ok, cleaned}` when every field is valid, otherwise
  `{:error, errors}` where `errors` maps a path (list of string keys and
  integer list indices) to a reason atom.
  """
  @spec sanitize(map(), map()) :: {:ok, map()} | {:error, map()}
  def sanitize(params, schema) when is_map(params) and is_map(schema) do
    {clean, errors} = walk_map(params, schema, [])

    if errors == %{} do
      {:ok, clean}
    else
      {:error, errors}
    end
  end

  # ── Recursion over a map/schema ────────────────────────────────────────────

  defp walk_map(params, schema, path) do
    Enum.reduce(schema, {%{}, %{}}, fn {key, spec}, {acc, errs} ->
      case Map.fetch(params, key) do
        :error ->
          {acc, errs}

        {:ok, value} ->
          case apply_spec(value, spec, path ++ [key]) do
            {:ok, cleaned} -> {Map.put(acc, key, cleaned), errs}
            {:error, field_errs} -> {acc, Map.merge(errs, field_errs)}
          end
      end
    end)
  end

  # ── Field spec dispatch ────────────────────────────────────────────────────

  defp apply_spec(value, {:list, inner}, path) do
    if is_list(value) do
      {clean, errs, _} =
        Enum.reduce(value, {[], %{}, 0}, fn item, {acc, e, i} ->
          case apply_spec(item, inner, path ++ [i]) do
            {:ok, c} -> {[c | acc], e, i + 1}
            {:error, fe} -> {acc, Map.merge(e, fe), i + 1}
          end
        end)

      if errs == %{}, do: {:ok, Enum.reverse(clean)}, else: {:error, errs}
    else
      {:error, %{path => :expected_list}}
    end
  end

  defp apply_spec(value, spec, path) when is_map(spec) do
    if is_map(value) do
      {clean, errs} = walk_map(value, spec, path)
      if errs == %{}, do: {:ok, clean}, else: {:error, errs}
    else
      {:error, %{path => :expected_map}}
    end
  end

  defp apply_spec(value, type, path) when is_atom(type) do
    case sanitize_field(type, value) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, %{path => reason}}
    end
  end

  # ── Leaf field sanitizers ──────────────────────────────────────────────────

  defp sanitize_field(:text, v) when is_binary(v), do: {:ok, escape_text(v)}
  defp sanitize_field(:text, _), do: {:error, :not_a_string}

  defp sanitize_field(:identifier, v) when is_binary(v), do: sql_identifier(v)
  defp sanitize_field(:identifier, _), do: {:error, :not_a_string}

  defp sanitize_field(:filename, v) when is_binary(v), do: filename(v)
  defp sanitize_field(:filename, _), do: {:error, :not_a_string}

  defp sanitize_field(:integer, v) when is_integer(v), do: {:ok, v}

  defp sanitize_field(:integer, v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {n, ""} -> {:ok, n}
      _ -> {:error, :not_an_integer}
    end
  end

  defp sanitize_field(:integer, _), do: {:error, :not_an_integer}

  defp sanitize_field(:boolean, v) when is_boolean(v), do: {:ok, v}
  defp sanitize_field(:boolean, "true"), do: {:ok, true}
  defp sanitize_field(:boolean, "false"), do: {:ok, false}
  defp sanitize_field(:boolean, _), do: {:error, :not_a_boolean}

  defp sanitize_field(type, _), do: {:error, {:unknown_field_type, type}}

  # ── Public helpers ─────────────────────────────────────────────────────────

  @doc "Safe SQL identifier (`{:ok, s}` or `{:error, :empty}`)."
  @spec sql_identifier(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def sql_identifier(input) when is_binary(input) do
    sanitized = String.replace(input, ~r/[^a-zA-Z0-9_]/, "")

    cond do
      sanitized == "" -> {:error, :empty}
      String.match?(sanitized, ~r/\A[0-9]/) -> {:ok, "_" <> sanitized}
      true -> {:ok, sanitized}
    end
  end

  @doc "Safe filename (`{:ok, s}` or `{:error, :empty}`)."
  @spec filename(String.t()) :: {:ok, String.t()} | {:error, :empty}
  def filename(input) when is_binary(input) do
    sanitized =
      input
      |> String.replace("\0", "")
      |> String.replace("/", "")
      |> String.replace("\\", "")
      |> String.replace(~r/[^a-zA-Z0-9_\-.]/, "")
      |> String.replace(~r/\.{2,}/, ".")
      |> String.trim(".")

    if sanitized == "" do
      {:error, :empty}
    else
      {:ok, sanitized}
    end
  end

  # ── Text escaping ──────────────────────────────────────────────────────────

  defp escape_text(v) do
    v
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/, "")
    |> String.trim()
    |> html_escape()
  end

  defp html_escape(s) do
    # TODO
  end
end
```

Give me only the complete implementation of `html_escape` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
