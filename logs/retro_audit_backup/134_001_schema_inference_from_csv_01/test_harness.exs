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
end
