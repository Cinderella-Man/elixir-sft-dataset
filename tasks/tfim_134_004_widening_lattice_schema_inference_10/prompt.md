# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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
defmodule LatticeSchemaTest do
  use ExUnit.Case, async: false

  defp schema(csv, opts \\ []), do: LatticeSchema.infer_string(csv, opts)

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

  test "numeric widening: integers plus a float become float" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => :float}
  end

  test "temporal widening: a mix of dates and datetimes becomes datetime" do
    csv = """
    ts
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"ts" => :datetime}
  end

  test "temporal widening also folds the space-separated datetime form" do
    csv = """
    ts
    2020-01-15
    2020-01-15 10:00:00
    2021-06-30
    """

    assert schema(csv) == %{"ts" => :datetime}
  end

  test "a column of pure dates in multiple formats stays date" do
    csv = """
    d
    2020-01-15
    03/25/2021
    """

    assert schema(csv) == %{"d" => :date}
  end

  test "a column of pure datetimes stays datetime" do
    csv = """
    ts
    2020-01-01 12:00:00
    2021-06-15T08:30:45
    """

    assert schema(csv) == %{"ts" => :datetime}
  end

  test "cross-family mixes still widen to the string top" do
    csv = """
    a,b,c
    1,2020-01-15,true
    2020-01-15T10:00:00,5,7
    """

    # a: integer + datetime -> string
    # b: date + integer -> string
    # c: boolean + integer -> string
    assert schema(csv) == %{"a" => :string, "b" => :string, "c" => :string}
  end

  test "invalid calendar dates fall back to string and drag the column to string" do
    csv = """
    d
    2020-01-15
    13/45/2020
    """

    assert schema(csv) == %{"d" => :string}
  end

  test "null cells never affect the join" do
    # TODO
  end

  test "quoted values are strings regardless of contents" do
    csv = """
    code
    "2020-01-15"
    "2020-01-15T10:00:00"
    """

    assert schema(csv) == %{"code" => :string}
  end

  test "an all-null column is typed as string" do
    csv = """
    a,b
    1,
    2,
    """

    assert schema(csv) == %{"a" => :integer, "b" => :string}
  end

  test "sample_rows bounds which rows drive the join" do
    csv = """
    ts
    2020-01-15
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv, sample_rows: 2) == %{"ts" => :date}
    assert schema(csv) == %{"ts" => :datetime}
  end

  test "headers: false generates positional names" do
    csv = """
    2020-01-15,1
    2020-01-15T10:00:00,2
    """

    assert schema(csv, headers: false) == %{
             "column_1" => :datetime,
             "column_2" => :integer
           }
  end

  test "infer_file reads and infers from a file on disk" do
    path =
      Path.join(
        System.tmp_dir!(),
        "lattice_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    File.write!(path, """
    id,when
    1,2020-01-15
    2,2020-01-15T10:00:00
    """)

    on_exit(fn -> File.rm(path) end)

    assert LatticeSchema.infer_file(path) == %{
             "id" => :integer,
             "when" => :datetime
           }
  end
end
```
