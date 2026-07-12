# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir module called `Sanitizer` that sanitizes **nested parameter maps** against a declarative schema — think mass-assignment protection plus per-field cleaning for controller params.

The core function is `Sanitizer.sanitize(params, schema)` where `params` is a (possibly deeply nested) map with **string keys** and `schema` describes how to treat each key.

A schema is itself a map with string keys. Each value (a "field spec") is one of:

- An **atom field type**:
  - `:text` — HTML-escape the value and clean it. Strip C0 control characters (except tab `\t`, newline `\n`, carriage return `\r`), trim surrounding whitespace, then escape `&`, `<`, `>`, `"`, and `'` to `&amp;`, `&lt;`, `&gt;`, `&quot;`, and `&#39;` respectively. Always succeeds for binaries; a non-binary is an error (`:not_a_string`).
  - `:identifier` — safe SQL identifier. Keep only `[A-Za-z0-9_]`. If empty after stripping → error `:empty`. If it starts with a digit, prepend `_`. Non-binary → `:not_a_string`.
  - `:filename` — safe filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to a single dot, trim leading/trailing dots. Empty result → `:empty`. Non-binary → `:not_a_string`.
  - `:integer` — accept an integer as-is; accept a binary that parses cleanly to an integer (after trimming); otherwise error `:not_an_integer`.
  - `:boolean` — accept `true`/`false`, or the strings `"true"`/`"false"`; otherwise error `:not_a_boolean`.
- A **`{:list, inner}`** tuple — the value must be a list; apply `inner` (itself a field spec) to every element.
- A **nested schema map** — the value must be a map; recurse.

Rules:

- **Whitelist semantics:** only keys present in the schema survive into the output. Any key in `params` that is not in the schema is dropped.
- **Missing keys:** a schema key with no corresponding key in `params` is simply skipped (not an error, not present in output).
- **Errors:** collect *all* field errors keyed by their **path** (a list of segments — string keys and integer list indices, e.g. `["profile", "handle"]` or `["scores", 1]`). If there are no errors, return `{:ok, cleaned_map}`. If there is at least one error, return `{:error, errors_map}` where `errors_map` maps each failing path to its reason atom.

Also expose `Sanitizer.sql_identifier/1` and `Sanitizer.filename/1` as public helpers returning `{:ok, string}` or `{:error, :empty}`.

Give me the complete module in a single file, standard library only — no external dependencies.

## Additional interface contract

- Type-shape mismatches get dedicated reason atoms: when a nested schema map is expected but the value is not a map, report `:expected_map` at that field's path; when a `{:list, inner}` spec is given a non-list value, report `:expected_list`. E.g. `sanitize(%{"profile" => "nope"}, %{"profile" => %{"bio" => :text}})` returns `{:error, %{["profile"] => :expected_map}}`, and `sanitize(%{"tags" => "nope"}, %{"tags" => {:list, :text}})` returns `{:error, %{["tags"] => :expected_list}}`.

## The buggy module

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
      {:error, clean}
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
7 of 15 test(s) failed:

  * test Sanitizer.sanitize/2 happy path cleans a fully valid nested payload
      
      
      match (=) failed
      code:  assert {:ok, out} = Sanitizer.sanitize(params, schema())
      left:  {:ok, out}
      right: {:error, %{"active" => true, "age" => 42, "avatar" => "pic.png", "name" => "Alice &lt;b&gt;", "profile" => %{"bio" => "hi &amp; bye", "handle" => "_1cool"}, "scores" => [1, 2, 3], "table" => "users", "tags" => ["a &amp; b", "&lt;x&gt;"]}}
      

  * test Sanitizer.sanitize/2 happy path drops keys that are not in the schema (whitelist)
      
      
      match (=) failed
      code:  assert {:ok, out} = Sanitizer.sanitize(params, schema())
      left:  {:ok, out}
      right: {:error, %{"name" => "bob"}}
      

  * test Sanitizer.sanitize/2 happy path missing schema keys are skipped, not errored
      
      
      match (=) failed
      code:  assert {:ok, out} = Sanitizer.sanitize(%{"name" => "x"}, schema())
      left:  {:ok, out}
      right: {:error, %{"name" => "x"}}
      

  * test Sanitizer.sanitize/2 field cleaning text escapes html special chars and trims
      
      
      match (=) failed
      code:  assert {:ok, %{"name" => "&amp;&lt;&gt;&quot;&#39;"}} =
                    Sanitizer.sanitize(%{"name" => ~s(  &<>"'  )}, %{"name" => :text})
      left:  {:ok, %{"name" => "&amp;&lt;&gt;&quot;&#39;"}}
      right: {:error, %{"name" => "&amp;&lt;&gt;&quot;&#39;"}}
      

  (…3 more)
```
