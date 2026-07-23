# The tests are the spec

Below is a complete, self-contained ExUnit suite. It is the only
specification you get: build the module (or modules) it exercises until
every test passes. Reach for nothing beyond what the tests themselves
require — the standard library and OTP unless the suite says otherwise.
House style applies (`@moduledoc`, `@doc` + `@spec` on the public API,
no compiler warnings).

## The test suite

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
    csv = ~s("x,y",1\n"x,z",2\n)

    assert schema(csv, headers: false) == %{
             "column_1" => %{type: :string, nullable: false, unique: true},
             "column_2" => %{type: :integer, nullable: false, unique: true}
           }
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

Send back the implementation only — one file, no tests.
