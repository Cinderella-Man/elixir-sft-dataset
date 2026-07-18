# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `split_records` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Schema Inference from CSV — Widening-Lattice Resolution

Write me an Elixir module called `LatticeSchema` that reads CSV data and infers each column's type by **joining its cell categories in a type-widening lattice** rather than the base task's ad-hoc "same-or-string" rule. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

- `LatticeSchema.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `LatticeSchema.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map `%{"column_name" => :inferred_type}` where each type is one of `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.

### Options

- `:headers` (boolean, default `true`) — when `true`, the first record is the header row supplying column names; when `false`, all records are data and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer from at most the first N data rows.

## CSV parsing rules

RFC-4180 style, identical to the base task: `\n` record separator with a single trailing newline ignored; comma field separator; double-quoted fields may contain commas; doubled quotes (`""`) are a literal quote; track whether each field was quoted. An **unquoted empty field** is null (ignored for inference); a quoted empty field (`""`) is a non-null empty string value.

## Per-cell categories

For each non-null cell, classify exactly as in the base task: quoted fields are always `string`; otherwise `boolean` (`true`/`false`, case-insensitive), `integer` (`^[+-]?\d+$`), `float` (`^[+-]?\d+\.\d+$`), `date` (valid `YYYY-MM-DD` or `MM/DD/YYYY`), `datetime` (valid `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`), else `string`. Values are used verbatim.

## Column type resolution — the lattice join (this is the difference)

Instead of "all-same-or-else-string", resolve each column by folding its distinct non-null categories through a binary **join** in a widening lattice:

- A column with **no** non-null cells → `:string`.
- The join of a category with itself is that category.
- **Numeric widening:** `integer` and `float` join to `:float` (so an integer/float mix is `:float`, exactly like the base task).
- **Temporal widening:** `date` and `datetime` join to `:datetime` — because a date is a less-precise datetime, a column mixing plain dates and datetimes widens to `:datetime` (this is where the lattice differs from the base task, which would return `:string`).
- Any other pair of distinct categories joins to `:string` (the lattice top). For example: `integer`+`datetime` → `:string`, `boolean`+`integer` → `:string`, `date`+`string` → `:string`.

The join must be commutative and associative, so folding the whole set of distinct categories yields a single well-defined type regardless of order. Concretely:

- All integers → `:integer`; add one float → `:float`.
- All dates (even in different date formats) → `:date`.
- All datetimes → `:datetime`.
- A mix of dates and datetimes → `:datetime`.
- A mix of dates and integers → `:string`.
- Null cells never affect the result.

## The module with `split_records` missing

```elixir
defmodule LatticeSchema do
  @moduledoc """
  CSV schema inference whose column resolution is a join over a type-widening
  lattice, using only the OTP standard library.

  Cells are classified into categories exactly as in the base task, but a
  column's type is the fold of its distinct non-null categories through a
  commutative, associative binary `join/2`: `integer`/`float` widen to
  `:float`, `date`/`datetime` widen to `:datetime`, and any other distinct
  pair widens to `:string` (the lattice top). An empty column is `:string`.
  """

  @numeric MapSet.new([:integer, :float])
  @temporal MapSet.new([:date, :datetime])

  @type schema :: %{optional(String.t()) => atom()}
  @type cell :: {String.t(), boolean()}
  @type row :: [cell()]

  @doc """
  Infers a schema from CSV `csv` given as a string.

  Returns a map of `%{"column_name" => type}` where each type is the join of
  the column's distinct non-null cell categories in the widening lattice.

  Options: `:headers` (boolean, default `true`) and `:sample_rows`
  (positive integer, default `100`).
  """
  @spec infer_string(String.t(), keyword()) :: schema()
  def infer_string(csv, opts \\ []) when is_binary(csv) do
    headers? = Keyword.get(opts, :headers, true)
    sample = Keyword.get(opts, :sample_rows, 100)

    records = parse_csv(csv)
    {names, data_rows} = split_records(records, headers?)
    sampled = Enum.take(data_rows, sample)
    names = names || default_names(sampled)

    names
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, resolve(column_cells(sampled, index))}
    end)
  end

  @doc """
  Reads the file at `path` and infers its schema.

  Behaves exactly as if the file's contents were passed to `infer_string/2`;
  accepts the same options.
  """
  @spec infer_file(Path.t(), keyword()) :: schema()
  def infer_file(path, opts \\ []) do
    path
    |> File.read!()
    |> infer_string(opts)
  end

  # --- Lattice resolution ---------------------------------------------------

  @spec resolve([cell()]) :: atom()
  defp resolve(cells) do
    cells
    |> Enum.map(&categorize/1)
    |> Enum.reject(&(&1 == :null))
    |> Enum.uniq()
    |> Enum.reduce(:bottom, &join/2)
    |> case do
      :bottom -> :string
      type -> type
    end
  end

  @spec join(atom(), atom()) :: atom()
  defp join(:bottom, x), do: x
  defp join(x, :bottom), do: x
  defp join(x, x), do: x

  defp join(a, b) do
    pair = MapSet.new([a, b])

    cond do
      MapSet.subset?(pair, @numeric) -> :float
      MapSet.subset?(pair, @temporal) -> :datetime
      true -> :string
    end
  end

  # --- Schema helpers -------------------------------------------------------

  defp split_records([], true) do
    # TODO
  end

  @spec default_names([row()]) :: [String.t()]
  defp default_names(rows) do
    ncols =
      case Enum.map(rows, &length/1) do
        [] -> 0
        lengths -> Enum.max(lengths)
      end

    Enum.map(1..ncols//1, fn i -> "column_#{i}" end)
  end

  @spec column_cells([row()], non_neg_integer()) :: [cell()]
  defp column_cells(rows, index) do
    Enum.flat_map(rows, fn row ->
      case Enum.at(row, index) do
        nil -> []
        cell -> [cell]
      end
    end)
  end

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
    [date_part, time_part] = String.split(value, sep, parts: 2)
    [y, m, d] = String.split(date_part, "-")
    [h, mi, s] = String.split(time_part, ":")

    result =
      NaiveDateTime.new(
        to_int(y),
        to_int(m),
        to_int(d),
        to_int(h),
        to_int(mi),
        to_int(s)
      )

    match?({:ok, _}, result)
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

Give me only the complete implementation of `split_records` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
