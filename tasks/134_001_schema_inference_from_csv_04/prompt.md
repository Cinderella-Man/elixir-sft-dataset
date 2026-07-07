# Fill in the middle: `date?/1`

Implement the private `date?/1` function for the `SchemaInference` module below.

`date?/1` takes a single string `value` and returns a boolean indicating whether
that value is a **valid calendar date** in one of two supported formats:

- `YYYY-MM-DD` — four digits, a hyphen, two digits, a hyphen, two digits.
- `MM/DD/YYYY` — two digits, a slash, two digits, a slash, four digits.

Behaviour:

- First check the value's **shape** with a regular expression anchored at both
  ends (`^…$`) so partial matches don't count.
  - For the `YYYY-MM-DD` shape, split the value on `"-"` to obtain the year,
    month and day parts (in that order).
  - For the `MM/DD/YYYY` shape, split the value on `"/"` to obtain the month,
    day and year parts (in that order).
- Convert each part to an integer (use the existing `to_int/1` helper) and check
  that the year/month/day form a real calendar date using the existing
  `valid_date?/3` helper (which is backed by `Date.new/3`). This means values
  that merely *look* like dates but are not valid calendar dates (e.g.
  `13/45/2020`) must return `false`.
- Any value that matches neither shape returns `false`.

Everything else in the module is already implemented — only fill in the body of
`date?/1`.

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
    # TODO
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

  @spec strip_one_newline(String.t()) :: String.t()
  defp strip_one_newline(content) do
    size = byte_size(content)

    case content do
      <<prefix::binary-size(^size - 1), "\n">> when size > 0 -> prefix
      _ -> content
    end
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