# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SchemaInferenceTest do
  use ExUnit.Case, async: false

  defp schema(csv, opts \\ []), do: SchemaInference.infer_string(csv, opts)

  # ------------------------------------------------------------------
  # Basic inference across all supported types
  # ------------------------------------------------------------------

  test "infers basic column types" do
    csv = """
    name,age,height,active,birth,created
    Alice,30,5.5,true,2020-01-15,2020-01-15T10:30:00
    Bob,25,6.0,false,1999-12-31,1999-12-31T08:00:00
    """

    assert schema(csv) == %{
             "name" => :string,
             "age" => :integer,
             "height" => :float,
             "active" => :boolean,
             "birth" => :date,
             "created" => :datetime
           }
  end

  # ------------------------------------------------------------------
  # Integer / float promotion
  # ------------------------------------------------------------------

  test "a column of all integers is integer" do
    csv = """
    n
    1
    2
    3
    """

    assert schema(csv) == %{"n" => :integer}
  end

  test "a column that is all integers except one float is a float" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => :float}
  end

  test "a column of all floats is float, including whole-number floats" do
    csv = """
    ratio
    2.0
    0.5
    100.25
    """

    assert schema(csv) == %{"ratio" => :float}
  end

  test "signed integers and floats are recognized" do
    csv = """
    i,f
    -5,-0.5
    +3,+1.25
    """

    assert schema(csv) == %{"i" => :integer, "f" => :float}
  end

  # ------------------------------------------------------------------
  # Mixed types default to string
  # ------------------------------------------------------------------

  test "a column with mixed unrelated types defaults to string" do
    csv = """
    val
    1
    hello
    """

    assert schema(csv) == %{"val" => :string}
  end

  test "a mix of date and datetime cells defaults to string" do
    csv = """
    x
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"x" => :string}
  end

  # ------------------------------------------------------------------
  # Null / empty handling
  # ------------------------------------------------------------------

  test "an all-null (empty) column is typed as string" do
    csv = """
    a,b
    1,
    2,
    """

    assert schema(csv) == %{"a" => :integer, "b" => :string}
  end

  test "null cells are ignored within an otherwise-typed column" do
    csv = """
    a,b
    1,x
    ,y
    3,z
    """

    assert schema(csv) == %{"a" => :integer, "b" => :string}
  end

  test "a header row with no data rows yields all-string columns" do
    csv = """
    a,b,c
    """

    assert schema(csv) == %{"a" => :string, "b" => :string, "c" => :string}
  end

  # ------------------------------------------------------------------
  # Quoted values
  # ------------------------------------------------------------------

  test "quoted numbers are strings, not integers" do
    csv = """
    code
    "123"
    "456"
    """

    assert schema(csv) == %{"code" => :string}
  end

  test "quoted fields containing commas are parsed as a single field" do
    csv = """
    amount,label
    "1,000",x
    "2,000",y
    """

    assert schema(csv) == %{"amount" => :string, "label" => :string}
  end

  # ------------------------------------------------------------------
  # Booleans
  # ------------------------------------------------------------------

  test "booleans are matched case-insensitively" do
    csv = """
    flag
    TRUE
    False
    """

    assert schema(csv) == %{"flag" => :boolean}
  end

  # ------------------------------------------------------------------
  # Dates and datetimes
  # ------------------------------------------------------------------

  test "a column with dates in multiple formats is still date" do
    csv = """
    d
    2020-01-15
    03/25/2021
    """

    assert schema(csv) == %{"d" => :date}
  end

  test "invalid calendar dates fall back to string" do
    csv = """
    d
    2020-01-15
    13/45/2020
    """

    assert schema(csv) == %{"d" => :string}
  end

  test "datetimes with a space separator are recognized" do
    csv = """
    ts
    2020-01-01 12:00:00
    2021-06-15 08:30:45
    """

    assert schema(csv) == %{"ts" => :datetime}
  end

  # ------------------------------------------------------------------
  # Options: sample_rows and headers
  # ------------------------------------------------------------------

  test "sample_rows limits how many data rows influence inference" do
    csv = """
    n
    1
    2
    3.5
    """

    assert schema(csv, sample_rows: 2) == %{"n" => :integer}
    assert schema(csv) == %{"n" => :float}
  end

  test "headers: false generates positional column names" do
    csv = """
    1,2.5
    3,4.5
    """

    assert schema(csv, headers: false) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end

  # ------------------------------------------------------------------
  # File-based API
  # ------------------------------------------------------------------

  test "infer_file reads and infers from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "schema_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,price,label
    1,9.99,"A,B"
    2,19.99,C
    """)

    on_exit(fn -> File.rm(path) end)

    assert SchemaInference.infer_file(path) == %{
             "id" => :integer,
             "price" => :float,
             "label" => :string
           }
  end

  test "sample_rows defaults to exactly 100 data rows" do
    rows = Enum.map(1..100, fn _ -> "1" end) ++ ["3.5"]
    csv = Enum.join(["n" | rows], "\n") <> "\n"

    assert schema(csv) == %{"n" => :integer}
    assert schema(csv, sample_rows: 101) == %{"n" => :float}
  end

  test "a quoted empty field counts as a non-null string cell" do
    csv = """
    a
    1
    ""
    2
    """

    assert schema(csv) == %{"a" => :string}
  end

  test "values with surrounding whitespace are not trimmed before detection" do
    csv = "n,f\n 1 , 2.5 \n 3 , 4.5 \n"

    assert schema(csv) == %{"n" => :string, "f" => :string}
  end

  test "a doubled quote inside a quoted header becomes one literal quote" do
    # TODO
  end

  test "a datetime with an impossible calendar date falls back to string" do
    csv = """
    ts
    2020-02-30T10:00:00
    2021-01-01 24:00:00
    """

    assert schema(csv) == %{"ts" => :string}
  end

  test "infer_file forwards options to infer_string" do
    path =
      Path.join(
        System.tmp_dir!(),
        "schema_opts_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, "1,2.5\n3,4.5\n")
    on_exit(fn -> File.rm(path) end)

    assert SchemaInference.infer_file(path, headers: false) == %{
             "column_1" => :integer,
             "column_2" => :float
           }
  end
end
```
