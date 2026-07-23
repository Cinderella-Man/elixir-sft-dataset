# One test is missing its body

Module plus harness below; a single `test` body was replaced with
`# TODO`. Reconstruct it from its name and the surrounding suite so the
harness passes for a correct implementation of the module. Touch nothing
else.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SchemaProfilerTest do
  use ExUnit.Case, async: false

  defp schema(csv, opts \\ []), do: SchemaProfiler.infer_string(csv, opts)

  test "infers type, nullability, and uniqueness together" do
    csv = """
    name,age
    Alice,30
    Bob,25
    """

    assert schema(csv) == %{
             "name" => %{type: :string, nullable: false, unique: true},
             "age" => %{type: :integer, nullable: false, unique: true}
           }
  end

  test "nullable is true when an unquoted empty field appears" do
    csv = """
    a,b
    1,x
    ,x
    """

    result = schema(csv)
    assert result["a"] == %{type: :integer, nullable: true, unique: true}
    assert result["b"] == %{type: :string, nullable: false, unique: false}
  end

  test "unique is false when non-null values repeat" do
    csv = """
    n
    1
    2
    2
    """

    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: false}}
  end

  test "duplicate nulls do not break uniqueness of the non-null values" do
    csv = """
    n
    1
    ,
    2
    """

    # second data row: n is empty (null), ignored for both type and uniqueness
    assert schema(csv) == %{"n" => %{type: :integer, nullable: true, unique: true}}
  end

  test "an all-null column is string, nullable, and trivially unique" do
    csv = """
    a,b
    1,
    2,
    """

    result = schema(csv)
    assert result["a"] == %{type: :integer, nullable: false, unique: true}
    assert result["b"] == %{type: :string, nullable: true, unique: true}
  end

  test "header row with no data rows is non-nullable and unique" do
    csv = """
    a,b,c
    """

    assert schema(csv) == %{
             "a" => %{type: :string, nullable: false, unique: true},
             "b" => %{type: :string, nullable: false, unique: true},
             "c" => %{type: :string, nullable: false, unique: true}
           }
  end

  test "quoted numbers are strings and their repetition breaks uniqueness" do
    csv = """
    code
    "1"
    "1"
    """

    assert schema(csv) == %{"code" => %{type: :string, nullable: false, unique: false}}
  end

  test "integer/float promotion still applies to the type" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => %{type: :float, nullable: false, unique: true}}
  end

  test "missing fields (ragged rows) count as null" do
    csv = """
    1,2
    3
    """

    result = schema(csv, headers: false)
    assert result["column_1"] == %{type: :integer, nullable: false, unique: true}
    assert result["column_2"] == %{type: :integer, nullable: true, unique: true}
  end

  test "sample_rows limits both type and profile computation" do
    csv = """
    n
    1
    2
    2
    """

    # first two rows only: no duplicates seen, no float seen
    assert schema(csv, sample_rows: 2) == %{
             "n" => %{type: :integer, nullable: false, unique: true}
           }

    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: false}}
  end

  test "infer_file reads and profiles from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "profile_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,label
    1,a
    2,a
    """)

    on_exit(fn -> File.rm(path) end)

    assert SchemaProfiler.infer_file(path) == %{
             "id" => %{type: :integer, nullable: false, unique: true},
             "label" => %{type: :string, nullable: false, unique: false}
           }
  end

  test "a quoted field keeps its comma instead of splitting into another column" do
    # TODO
  end

  test "a doubled quote collapses to one literal quote and stays inside the quoted field" do
    csv = ~s(q\n"a"",b"\n"a,b"\n)

    # row 1 is the value `a",b`, row 2 is `a,b` — distinct, so the column stays unique
    assert schema(csv) == %{"q" => %{type: :string, nullable: false, unique: true}}
  end

  test "a quoted empty field is a non-null string value" do
    csv = ~s(a,b\n"",1\nx,2\n)

    result = schema(csv)
    assert result["a"] == %{type: :string, nullable: false, unique: true}
    assert result["b"] == %{type: :integer, nullable: false, unique: true}
  end

  test "a quoted value duplicates an unquoted one with the same characters" do
    csv = ~s(code\n1\n"1"\n)

    assert schema(csv) == %{"code" => %{type: :string, nullable: false, unique: false}}
  end

  test "sample_rows defaults to 100 data rows" do
    body = Enum.map_join(1..100, "", fn i -> "#{i}\n" end)
    csv = "n\n" <> body <> "1\n"

    # the 101st data row repeats "1" but falls outside the default sample
    assert schema(csv) == %{"n" => %{type: :integer, nullable: false, unique: true}}

    assert schema(csv, sample_rows: 101) == %{
             "n" => %{type: :integer, nullable: false, unique: false}
           }
  end

  test "real calendar dates and datetimes classify while impossible dates fall back to string" do
    csv = """
    d,ts,bad,flag
    2020-01-31,2020-01-31T10:00:00,2020-02-30,TRUE
    03/04/2021,2021-03-04 08:30:00,13/01/2021,False
    """

    result = schema(csv)
    assert result["d"] == %{type: :date, nullable: false, unique: true}
    assert result["ts"] == %{type: :datetime, nullable: false, unique: true}
    assert result["bad"] == %{type: :string, nullable: false, unique: true}
    assert result["flag"] == %{type: :boolean, nullable: false, unique: true}
  end
end
```
