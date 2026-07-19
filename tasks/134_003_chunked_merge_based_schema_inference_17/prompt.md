# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `valid_datetime?` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Schema Inference from CSV — Chunked Merge-Based Inference

Write me an Elixir module called `MergeSchema` that infers CSV column types, but is built so a large file can be inferred **in independent chunks that are merged**. Each chunk is reduced to a compact *partial* inference state; partials combine with an associative, commutative, idempotent `merge/2`; and a final resolution step turns a partial into a schema. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

- `MergeSchema.partial(csv, opts \\ [])` — parse a CSV fragment and return an opaque **partial** inference state (a plain map).
- `MergeSchema.merge(partial_a, partial_b)` — combine two partials into one.
- `MergeSchema.finalize(partial)` — resolve a partial into a schema map `%{"column_name" => :inferred_type}`.
- `MergeSchema.infer_string(csv, opts \\ [])` — convenience: `finalize(partial(csv, opts))`.

The inferred type is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.

### Options (for `partial/2` and `infer_string/2`)

- `:headers` (boolean, default `true`) — when `true`, the **first record of that fragment** is a header row supplying column names; when `false`, all records are data and columns are positional (`"column_1"`, `"column_2"`, …, 1-indexed).

There is no `:sample_rows` option — a chunk is expected to already be a bounded slice of the file.

## Partial representation

A partial must be a plain map with exactly these keys:

- `:names` — the list of header column-name strings for this fragment, or `nil` when the fragment was parsed with `headers: false`. A fragment with **no records at all** (an empty string, or only a trailing newline) has no header row to consume, so its `:names` is `nil` — never `[]` — its `:ncols` is `0`, and its `:categories` is empty. That makes the empty-fragment partial a **neutral element** for `merge/2`: merging it with any partial `p`, in either order, must finalize exactly like `p` alone (an empty fragment must never mask the header carried by another chunk).
- `:ncols` — the number of columns observed (the max over the header length and every data row's field count).
- `:categories` — a map from 0-based column index to a `MapSet` of the **non-null cell categories** seen in that column (nulls are never added).

## CSV parsing rules

RFC-4180 style, identical to the base task: `\n` record separator with a single trailing newline ignored; comma field separator; double-quoted fields may contain commas; doubled quotes (`""`) are a literal quote; track whether each field was quoted. An **unquoted empty field** is null (ignored); a quoted empty field (`""`) is a non-null empty string value.

## Per-cell categories

For each non-null cell, classify exactly as in the base task: quoted fields are always `string`; otherwise `boolean` (`true`/`false`, case-insensitive), `integer` (`^[+-]?\d+$`), `float` (`^[+-]?\d+\.\d+$`), `date` (valid `YYYY-MM-DD` or `MM/DD/YYYY`), `datetime` (valid `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`), else `string`. Values are used verbatim.

## Merge semantics

`merge/2` must be **associative, commutative, and idempotent**:

- `:categories` — per-index `MapSet` union.
- `:ncols` — the maximum of the two.
- `:names` — the first non-`nil` of the two (`a.names || b.names`). In practice only one fragment (the first chunk) carries a header.

## Finalization

`finalize/1` resolves each column from its accumulated category set, using the base task's rules:

1. Empty set (all null / no data) → `:string`.
2. Exactly one category → that category.
3. A set that is a subset of `{integer, float}` → `:float`.
4. Otherwise → `:string`.

Column names come from `:names` when present; otherwise positional names `"column_1"`..`"column_ncols"` are generated from `:ncols`.

## The module with `valid_datetime?` missing

```elixir
defmodule MergeSchema do
  @moduledoc """
  Chunk-and-merge CSV schema inference using only the OTP standard library.

  A CSV fragment is reduced by `partial/2` to a compact state — header names,
  a column count, and per-column `MapSet`s of observed non-null categories.
  Partials combine with an associative, commutative, idempotent `merge/2`
  (per-index set union, max column count, first non-nil header list), and
  `finalize/1` resolves the accumulated categories into a schema map. This lets
  a large file be inferred in independent slices and folded together.
  """

  @type category :: atom()
  @type partial :: %{
          names: [String.t()] | nil,
          ncols: non_neg_integer(),
          categories: %{optional(non_neg_integer()) => MapSet.t(category())}
        }
  @type schema :: %{optional(String.t()) => atom()}
  @type cell :: {String.t(), boolean()}
  @type row :: [cell()]

  @doc """
  Parse a CSV fragment into an opaque partial inference state (a plain map).

  With `headers: true` (the default) the first record supplies column names;
  with `headers: false` every record is data and columns are positional. A
  fragment with no records at all has `:names` of `nil`, making it a neutral
  element for `merge/2`. The returned map has `:names`, `:ncols`, and
  `:categories` keys.
  """
  @spec partial(String.t(), keyword()) :: partial()
  def partial(csv, opts \\ []) when is_binary(csv) do
    headers? = Keyword.get(opts, :headers, true)

    records = parse_csv(csv)
    {names, data_rows} = split_records(records, headers?)

    ncols =
      [length(names || [])]
      |> Kernel.++(Enum.map(data_rows, &length/1))
      |> Enum.max()

    %{names: names, ncols: ncols, categories: build_categories(data_rows)}
  end

  @doc """
  Combine two partials into one.

  The operation is associative, commutative, and idempotent: `:categories` are
  unioned per index, `:ncols` is the maximum, and `:names` is the first
  non-`nil` header list.
  """
  @spec merge(partial(), partial()) :: partial()
  def merge(a, b) do
    %{
      names: a.names || b.names,
      ncols: max(a.ncols, b.ncols),
      categories:
        Map.merge(a.categories, b.categories, fn _index, s1, s2 -> MapSet.union(s1, s2) end)
    }
  end

  @doc """
  Resolve a partial into a schema map `%{"column_name" => :inferred_type}`.

  Column names come from `:names` when present, otherwise positional names
  `"column_1"`..`"column_ncols"` are generated from `:ncols`.
  """
  @spec finalize(partial()) :: schema()
  def finalize(%{names: names, ncols: ncols, categories: categories}) do
    resolved_names = names || Enum.map(1..ncols//1, fn i -> "column_#{i}" end)

    resolved_names
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, resolve(Map.get(categories, index, MapSet.new()))}
    end)
  end

  @doc """
  Convenience wrapper equivalent to `finalize(partial(csv, opts))`.
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) do
    csv
    |> partial(opts)
    |> finalize()
  end

  # --- Category accumulation ------------------------------------------------

  @spec build_categories([row()]) :: %{optional(non_neg_integer()) => MapSet.t(category())}
  defp build_categories(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      row
      |> Enum.with_index()
      |> Enum.reduce(acc, fn {cell, index}, inner ->
        case categorize(cell) do
          :null -> inner
          category -> Map.update(inner, index, MapSet.new([category]), &MapSet.put(&1, category))
        end
      end)
    end)
  end

  @spec resolve(MapSet.t(category())) :: atom()
  defp resolve(set) do
    case MapSet.to_list(set) do
      [] -> :string
      [category] -> category
      many -> if Enum.all?(many, &(&1 in [:integer, :float])), do: :float, else: :string
    end
  end

  # --- Schema helpers -------------------------------------------------------

  @spec split_records([row()], boolean()) :: {[String.t()] | nil, [row()]}
  defp split_records([], true), do: {nil, []}

  defp split_records([header | rest], true) do
    {Enum.map(header, fn {value, _quoted?} -> value end), rest}
  end

  defp split_records(records, false), do: {nil, records}

  # --- Per-cell classification ---------------------------------------------

  @spec categorize(cell()) :: atom()
  defp categorize({"", false}), do: :null
  defp categorize({_value, true}), do: :string
  defp categorize({value, false}), do: classify(value)

  @spec classify(String.t()) :: atom()
  defp classify(value) do
    cond do
      boolean?(value) -> :boolean
      integer?(value) -> :integer
      float?(value) -> :float
      date?(value) -> :date
      datetime?(value) -> :datetime
      true -> :string
    end
  end

  defp boolean?(value), do: String.downcase(value) in ["true", "false"]

  defp integer?(value), do: Regex.match?(~r/^[+-]?\d+$/, value)

  defp float?(value), do: Regex.match?(~r/^[+-]?\d+\.\d+$/, value)

  defp date?(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}$/, value) ->
        [y, m, d] = String.split(value, "-")
        valid_date?(to_int(y), to_int(m), to_int(d))

      Regex.match?(~r/^\d{2}\/\d{2}\/\d{4}$/, value) ->
        [m, d, y] = String.split(value, "/")
        valid_date?(to_int(y), to_int(m), to_int(d))

      true ->
        false
    end
  end

  defp datetime?(value) do
    cond do
      Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/, value) ->
        valid_datetime?(value, "T")

      Regex.match?(~r/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/, value) ->
        valid_datetime?(value, " ")

      true ->
        false
    end
  end

  defp valid_date?(year, month, day) do
    match?({:ok, _}, Date.new(year, month, day))
  end

  defp valid_datetime?(value, sep) do
    # TODO
  end

  defp to_int(value), do: String.to_integer(value)

  # --- CSV parsing ---------------------------------------------------------

  @spec parse_csv(String.t()) :: [row()]
  defp parse_csv(content) do
    case strip_one_newline(content) do
      "" -> []
      stripped -> parse_chars(stripped, "", false, false, [], [])
    end
  end

  defp strip_one_newline(content) do
    size = byte_size(content)

    case content do
      <<prefix::binary-size(^size - 1), "\n">> when size > 0 -> prefix
      _ -> content
    end
  end

  defp parse_chars(<<>>, acc, quoted?, _in_q?, fields, records) do
    record = Enum.reverse([{acc, quoted?} | fields])
    Enum.reverse([record | records])
  end

  defp parse_chars(<<"\"\"", rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc <> "\"", quoted?, true, fields, records)
  end

  defp parse_chars(<<"\"", rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc, quoted?, false, fields, records)
  end

  defp parse_chars(<<c::utf8, rest::binary>>, acc, quoted?, true, fields, records) do
    parse_chars(rest, acc <> <<c::utf8>>, quoted?, true, fields, records)
  end

  defp parse_chars(<<"\"", rest::binary>>, acc, _quoted?, false, fields, records) do
    parse_chars(rest, acc, true, true, fields, records)
  end

  defp parse_chars(<<",", rest::binary>>, acc, quoted?, false, fields, records) do
    parse_chars(rest, "", false, false, [{acc, quoted?} | fields], records)
  end

  defp parse_chars(<<"\n", rest::binary>>, acc, quoted?, false, fields, records) do
    record = Enum.reverse([{acc, quoted?} | fields])
    parse_chars(rest, "", false, false, [], [record | records])
  end

  defp parse_chars(<<c::utf8, rest::binary>>, acc, quoted?, false, fields, records) do
    parse_chars(rest, acc <> <<c::utf8>>, quoted?, false, fields, records)
  end
end
```

Give me only the complete implementation of `valid_datetime?` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
