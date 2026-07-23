# Reconstruct the missing typespec

In the otherwise-complete module below, the `@spec` for
`sanitize/2` has been removed; `# TODO: @spec` holds its place.
Write that one attribute — a `@spec` for `sanitize/2` faithful to
the arguments, guards, and every return shape the code can actually
produce. Nothing else changes.

## The module with the `@spec` for `sanitize/2` missing

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
  # TODO: @spec
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
    s
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
```

Reply with the `@spec` attribute alone, however many lines it needs —
not the module.
