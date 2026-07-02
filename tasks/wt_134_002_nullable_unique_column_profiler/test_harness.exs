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
end