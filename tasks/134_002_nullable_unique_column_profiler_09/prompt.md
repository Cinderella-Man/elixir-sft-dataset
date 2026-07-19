# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `column_cells` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Schema Inference from CSV — Nullable & Unique Column Profiler

Write me an Elixir module called `SchemaProfiler` that reads CSV data and, for each column, infers not just a type but a small **profile**: its inferred type, whether the column is nullable, and whether its values are unique. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

I need exactly these two functions:

- `SchemaProfiler.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `SchemaProfiler.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map of the form `%{"column_name" => %{type: t, nullable: n, unique: u}}` where:

- `type` is one of the atoms `:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`.
- `nullable` is a boolean.
- `unique` is a boolean.

### Options

- `:headers` (boolean, default `true`) — when `true`, the **first record** is the header row and supplies the column names. When `false`, there is no header row, every record is data, and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer from at most the **first N data rows** (data rows exclude the header). If there are fewer data rows than N, use all of them.

## CSV parsing rules

Parse CSV in the RFC-4180 style:

- Records are separated by newlines (`\n`). A single trailing newline at the end of the input must be ignored (it does not create an extra empty record).
- Fields within a record are separated by commas.
- A field may be **quoted** with double quotes (`"`). A quoted field may contain commas (literal, no split). Inside a quoted field, a doubled quote (`""`) represents a single literal quote character.
- Track whether each field was quoted — this affects type inference.

## Null / empty detection

- An **unquoted empty field** (zero-length) is treated as **null**.
- A quoted empty field (`""`) is a non-null empty **string** value.
- A cell that is **missing** because a data row is shorter than the column's field position is also treated as **null** for that column.

## Per-cell type detection (same as the base task)

For each **non-null** cell, classify it into exactly one category. **If a field was quoted in the source, its category is always `string`.** For unquoted fields:

- **boolean** — `true` or `false`, case-insensitive.
- **integer** — matches `^[+-]?\d+$`.
- **float** — matches `^[+-]?\d+\.\d+$` (so `2.0` is a float).
- **date** — a valid calendar date in `YYYY-MM-DD` or `MM/DD/YYYY`.
- **datetime** — a valid date-and-time in `YYYY-MM-DDTHH:MM:SS` or `YYYY-MM-DD HH:MM:SS`.
- **string** — anything else (including values that look like a date but are not real calendar dates).

Values are used verbatim (no whitespace trimming).

## Type resolution (same as the base task)

For each column, over the categories of its **non-null** cells:

1. No non-null cells → `:string`.
2. All the same category `c` → `c`.
3. A mix that is a subset of `{integer, float}` → `:float`.
4. Otherwise → `:string`.

## Nullability

`nullable` is `true` when the column has **at least one null cell** in the sampled data rows — either an unquoted empty field or a missing field (row shorter than the column position). Otherwise `false`. A header-only file (no data rows) yields `nullable: false` for every column.

## Uniqueness

`unique` is `true` when the column's **non-null values are all distinct**, comparing the verbatim field string values (ignoring the quoted flag). A column with zero or one non-null value is trivially `unique: true`. Null cells never count toward uniqueness.

## The module with `column_cells` missing

```elixir
defmodule SchemaProfiler do
  @moduledoc """
  Infers a per-column profile from CSV data using only the OTP standard library.

  Each column is described by a map `%{type: atom, nullable: boolean,
  unique: boolean}`. The `type` is resolved exactly as in the base schema
  inference task; `nullable` reports whether any sampled cell was null (an
  unquoted empty field or a field missing because the row was too short);
  `unique` reports whether the non-null verbatim field values are all distinct.
  """

  @type profile :: %{type: atom(), nullable: boolean(), unique: boolean()}
  @type schema :: %{optional(String.t()) => profile()}
  @type cell :: {String.t(), boolean()}
  @type row :: [cell()]

  @doc """
  Infers a per-column schema profile from the given CSV `csv` string.

  Returns a map of column name to `%{type: t, nullable: n, unique: u}`.
  See the module documentation for the supported options (`:headers` and
  `:sample_rows`).
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
    |> Map.new(fn {name, index} -> {name, profile(sampled, index)} end)
  end

  @doc """
  Reads the file at `path` and infers its schema profile.

  Behaves exactly as if the file's contents were passed to `infer_string/2`.
  """
  @spec infer_file(Path.t(), keyword()) :: schema()
  def infer_file(path, opts \\ []) do
    path
    |> File.read!()
    |> infer_string(opts)
  end

  # --- Profiling ------------------------------------------------------------

  @spec profile([row()], non_neg_integer()) :: profile()
  defp profile(rows, index) do
    cells = column_cells(rows, index)
    missing = length(rows) - length(cells)

    cell_cats = Enum.map(cells, fn cell -> {cell, categorize(cell)} end)

    nullable? = missing > 0 or Enum.any?(cell_cats, fn {_c, cat} -> cat == :null end)

    non_null = Enum.reject(cell_cats, fn {_c, cat} -> cat == :null end)
    values = Enum.map(non_null, fn {{value, _quoted?}, _cat} -> value end)
    categories = non_null |> Enum.map(fn {_c, cat} -> cat end) |> Enum.uniq()

    %{
      type: resolve(categories),
      nullable: nullable?,
      unique: length(values) == length(Enum.uniq(values))
    }
  end

  @spec resolve([atom()]) :: atom()
  defp resolve(categories) do
    case categories do
      [] -> :string
      [category] -> category
      many -> if Enum.all?(many, &(&1 in [:integer, :float])), do: :float, else: :string
    end
  end

  # --- Schema helpers -------------------------------------------------------

  @spec split_records([row()], boolean()) :: {[String.t()] | nil, [row()]}
  defp split_records([], true), do: {[], []}

  defp split_records([header | rest], true) do
    {Enum.map(header, fn {value, _quoted?} -> value end), rest}
  end

  defp split_records(records, false), do: {nil, records}

  @spec default_names([row()]) :: [String.t()]
  defp default_names(rows) do
    ncols =
      case Enum.map(rows, &length/1) do
        [] -> 0
        lengths -> Enum.max(lengths)
      end

    Enum.map(1..ncols//1, fn i -> "column_#{i}" end)
  end

  defp column_cells(rows, index) do
    # TODO
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

Give me only the complete implementation of `column_cells` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
