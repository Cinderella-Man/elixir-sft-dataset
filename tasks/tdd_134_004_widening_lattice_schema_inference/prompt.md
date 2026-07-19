# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

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
    csv = """
    x
    2020-01-15
    ,
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"x" => :datetime}
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

  test "a quoted empty field is a non-null string cell that widens the column" do
    csv = """
    a
    1
    ""
    """

    assert schema(csv) == %{"a" => :string}
  end

  test "sample_rows defaults to at most the first 100 data rows" do
    rows = List.duplicate("2020-01-15", 100)
    csv = Enum.join(["ts"] ++ rows ++ ["2020-01-15T10:00:00"], "\n") <> "\n"

    assert schema(csv) == %{"ts" => :date}
    assert schema(csv, sample_rows: 101) == %{"ts" => :datetime}
  end

  test "boolean detection is case-insensitive across mixed casings" do
    csv = """
    flag
    TRUE
    False
    tRuE
    """

    assert schema(csv) == %{"flag" => :boolean}
  end

  test "signed numerics classify per the documented regexes, partial decimals do not" do
    csv = """
    i,f,x
    +5,+1.5,1.
    -3,-2.25,.5
    """

    assert schema(csv) == %{"i" => :integer, "f" => :float, "x" => :string}
  end

  test "quoted header fields keep embedded commas and unescape doubled quotes" do
    csv = ~s|"first,last","say ""hi"""\n1,2\n|

    assert schema(csv) == %{"first,last" => :integer, "say \"hi\"" => :integer}
  end

  test "infer_file honors headers and sample_rows options like infer_string" do
    path =
      Path.join(
        System.tmp_dir!(),
        "lattice_opts_#{System.pid()}_#{System.unique_integer([:positive])}.csv"
      )

    contents = """
    2020-01-15,1
    2020-01-15T10:00:00,2
    """

    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)

    opts = [headers: false, sample_rows: 1]

    assert LatticeSchema.infer_file(path, opts) ==
             LatticeSchema.infer_string(contents, opts)

    assert LatticeSchema.infer_file(path, opts) ==
             %{"column_1" => :date, "column_2" => :integer}
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
