# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `strip_one_newline` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Schema Inference from CSV

Write me an Elixir module called `SchemaInference` that reads CSV data and infers the type of each column. Use only the OTP standard library — no external dependencies — and give me the complete module in a single file.

## Public API

I need exactly these two functions:

- `SchemaInference.infer_string(csv, opts \\ [])` — takes the CSV content as a string and returns the inferred schema.
- `SchemaInference.infer_file(path, opts \\ [])` — reads the file at `path` and returns the inferred schema (behaves exactly as if the file's contents were passed to `infer_string/2`).

Both return a plain map of the form `%{"column_name" => :inferred_type}`, where each type is one of the atoms:

`:string`, `:integer`, `:float`, `:boolean`, `:date`, `:datetime`

### Options

- `:headers` (boolean, default `true`) — when `true`, the **first record** is the header row and supplies the column names. When `false`, there is no header row, every record is data, and columns are named `"column_1"`, `"column_2"`, … (1-indexed, by field position).
- `:sample_rows` (positive integer, default `100`) — infer types from at most the **first N data rows** (data rows exclude the header). If there are fewer data rows than N, use all of them.

## CSV parsing rules

Parse CSV in the RFC-4180 style:

- Records are separated by newlines (`\n`). A single trailing newline at the end of the input must be ignored (i.e. it does not create an extra empty record).
- Fields within a record are separated by commas.
- A field may be **quoted** with double quotes (`"`). A quoted field may contain commas, which are literal and do **not** split the field. Inside a quoted field, a doubled quote (`""`) represents a single literal quote character.
- You must track whether each field was quoted in the source — this affects type inference (see below).

## Null / empty detection

- An **unquoted empty field** (zero-length, e.g. the value between the comma and the newline in `1,`) is treated as **null**. Null cells are ignored when inferring a column's type.
- A quoted empty field (`""`) is a non-null empty **string** value.

## Per-cell type detection

For each **non-null** cell, classify it into exactly one category. **If a field was quoted in the source, its category is always `string`, regardless of its contents** (so a column of quoted numbers infers to `:string`). For unquoted fields, use these rules (the shapes are mutually exclusive, so order does not matter):

- **boolean** — the value is `true` or `false`, matched case-insensitively (`TRUE`, `False`, etc.).
- **integer** — the value matches `^[+-]?\d+$` (an optional sign followed by one or more digits).
- **float** — the value matches `^[+-]?\d+\.\d+$` (an optional sign, digits, a decimal point, then digits). Note `2.0` is a float, not an integer.
- **date** — the value is a **valid calendar date** in one of these formats:
  - `YYYY-MM-DD`
  - `MM/DD/YYYY`
- **datetime** — the value is a **valid** date-and-time in one of these formats:
  - `YYYY-MM-DDTHH:MM:SS`
  - `YYYY-MM-DD HH:MM:SS`
- **string** — anything else (including any value that "looks like" a date but is not a real calendar date, e.g. `13/45/2020`).

## Column type resolution

For each column, look at the categories of all its non-null cells and resolve a single column type:

1. If the column has **no non-null cells** (all null, or no data rows at all) → `:string`.
2. If every non-null cell has the **same** category `c` → `c`.
3. Otherwise, if the set of categories is a subset of `{integer, float}` (i.e. a mix of integers and floats) → `:float`.
4. Otherwise → `:string`.

Some consequences to get right:

- A column of all integers → `:integer`; add a single float and it becomes `:float`.
- A column mixing genuinely different categories (e.g. a date and a datetime, or an integer and a word) → `:string`.
- A column whose dates appear in **different date formats** (some `YYYY-MM-DD`, some `MM/DD/YYYY`) is still `:date`, because every cell's category is `date`.
- Null cells never change the outcome — a column of `[1, null, 2]` is `:integer`.

Field values are used verbatim for detection (no whitespace trimming).

## The module with `strip_one_newline` missing

```elixir
defmodule SchemaInference do
  @moduledoc """
  Infers a simple column schema from CSV data using only the OTP standard
  library.

  The CSV is parsed in an RFC-4180 style (quoted fields, doubled quotes as
  escapes, comma field separators, `\\n` record separators). For each column
  the non-null cells are classified into one of a small set of categories and
  a single column type is resolved.

  Inferred types are one of the atoms `:string`, `:integer`, `:float`,
  `:boolean`, `:date` or `:datetime`. The result is a plain map of the form
  `%{"column_name" => :inferred_type}`.
  """

  @type schema :: %{optional(String.t()) => atom()}
  @type cell :: {String.t(), boolean()}
  @type row :: [cell()]

  @doc """
  Infers the schema from CSV `csv` given as a string.

  Options:

    * `:headers` (boolean, default `true`) — when `true` the first record is
      the header row supplying column names; when `false` all records are data
      and columns are named `"column_1"`, `"column_2"`, ….
    * `:sample_rows` (positive integer, default `100`) — infer from at most the
      first N data rows.
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
      {name, resolve_column(column_cells(sampled, index))}
    end)
  end

  @doc """
  Reads the file at `path` and infers the schema from its contents.

  Behaves exactly as if the file's contents were passed to `infer_string/2`.
  """
  @spec infer_file(Path.t(), keyword()) :: schema()
  def infer_file(path, opts \\ []) do
    path
    |> File.read!()
    |> infer_string(opts)
  end

  # --- Schema helpers ------------------------------------------------------

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

  @spec column_cells([row()], non_neg_integer()) :: [cell()]
  defp column_cells(rows, index) do
    Enum.flat_map(rows, fn row ->
      case Enum.at(row, index) do
        nil -> []
        cell -> [cell]
      end
    end)
  end

  @spec resolve_column([cell()]) :: atom()
  defp resolve_column(cells) do
    categories =
      cells
      |> Enum.map(&categorize/1)
      |> Enum.reject(&(&1 == :null))
      |> Enum.uniq()

    case categories do
      [] -> :string
      [category] -> category
      many -> if numeric_only?(many), do: :float, else: :string
    end
  end

  @spec numeric_only?([atom()]) :: boolean()
  defp numeric_only?(categories) do
    Enum.all?(categories, &(&1 in [:integer, :float]))
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

  @spec boolean?(String.t()) :: boolean()
  defp boolean?(value), do: String.downcase(value) in ["true", "false"]

  @spec integer?(String.t()) :: boolean()
  defp integer?(value), do: Regex.match?(~r/^[+-]?\d+$/, value)

  @spec float?(String.t()) :: boolean()
  defp float?(value), do: Regex.match?(~r/^[+-]?\d+\.\d+$/, value)

  @spec date?(String.t()) :: boolean()
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

  @spec datetime?(String.t()) :: boolean()
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

  @spec valid_date?(integer(), integer(), integer()) :: boolean()
  defp valid_date?(year, month, day) do
    match?({:ok, _}, Date.new(year, month, day))
  end

  @spec valid_datetime?(String.t(), String.t()) :: boolean()
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

  @spec to_int(String.t()) :: integer()
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
    # TODO
  end

  # State: accumulator, quoted?, in_quotes?, current fields (rev), records (rev)
  @spec parse_chars(binary(), String.t(), boolean(), boolean(), [cell()], [row()]) ::
          [row()]
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

Give me only the complete implementation of `strip_one_newline` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
