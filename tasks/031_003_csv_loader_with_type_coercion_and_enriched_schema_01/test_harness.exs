defmodule CsvLoaderTest.Helpers do
  def field(name, opts \\ []) do
    base = %{
      name: name,
      required: Keyword.get(opts, :required, true),
      type: Keyword.get(opts, :type, :string)
    }

    base
    |> maybe_put(:key, Keyword.get(opts, :key, nil))
    |> maybe_put(:format, Keyword.get(opts, :format, nil))
    |> maybe_put(:default, Keyword.get(opts, :default, nil))
    |> maybe_put(:values, Keyword.get(opts, :values, nil))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end

defmodule CsvLoaderTest do
  use ExUnit.Case, async: true
  import CsvLoaderTest.Helpers

  @basic_schema [
    field("name"),
    field("age", type: :integer),
    field("score", type: :float, required: false, default: 0.0),
    field("active", type: :boolean),
    field("joined", type: :date)
  ]

  # -------------------------------------------------------
  # Happy path — typed return values
  # -------------------------------------------------------

  test "imports a fully valid CSV with correctly typed values" do
    csv = """
    name,age,score,active,joined
    Alice,30,95.5,true,2024-01-15
    Bob,25,88.0,false,2023-06-01
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice.name == "Alice"
    assert alice.age == 30
    assert is_integer(alice.age)
    assert alice.score == 95.5
    assert is_float(alice.score)
    assert alice.active == true
    assert alice.joined == ~D[2024-01-15]
    assert bob.active == false
  end

  test "valid rows use atom keys" do
    csv = """
    name,age,active,joined
    Carol,40,1,2020-03-10
    """

    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, :name)
    assert Map.has_key?(row, :age)
    assert Map.has_key?(row, :active)
    assert Map.has_key?(row, :joined)
  end

  test "custom :key option overrides the atom key" do
    schema = [
      field("Full Name", key: :full_name),
      field("age", type: :integer)
    ]

    csv = """
    Full Name,age
    Alice Smith,30
    """

    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.full_name == "Alice Smith"
  end

  # -------------------------------------------------------
  # Type coercion specifics
  # -------------------------------------------------------

  test "integer coercion" do
    csv = "name,age,active,joined\nAlice,30,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.age == 30
    assert is_integer(row.age)
  end

  test "float coercion from decimal string" do
    csv = "name,age,score,active,joined\nAlice,30,3.14,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 3.14
    assert is_float(row.score)
  end

  test "float coercion from integer string" do
    csv = "name,age,score,active,joined\nAlice,30,42,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 42.0
    assert is_float(row.score)
  end

  test "boolean coercion accepts true/false/1/0 case-insensitively" do
    csv = """
    name,age,active,joined
    A,1,TRUE,2024-01-01
    B,2,False,2024-01-01
    C,3,0,2024-01-01
    D,4,1,2024-01-01
    """

    assert {:ok, valid, []} = CsvLoader.load_string(csv, @basic_schema)
    assert Enum.map(valid, & &1.active) == [true, false, false, true]
  end

  test "date coercion returns Date struct" do
    csv = "name,age,active,joined\nAlice,30,true,2024-12-25\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.joined == ~D[2024-12-25]
  end

  test "invalid date produces a type error" do
    csv = "name,age,active,joined\nAlice,30,true,not-a-date\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "joined", msg} = find_error(errors, 1, "joined")
    assert msg =~ "date"
  end

  test "date with invalid calendar date produces an error" do
    csv = "name,age,active,joined\nAlice,30,true,2024-02-30\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert find_error(errors, 1, "joined") != nil
  end

  # -------------------------------------------------------
  # Enum type
  # -------------------------------------------------------

  test "enum type accepts allowed values" do
    schema = [field("role", type: :enum, values: ["admin", "user", "guest"])]
    csv = "role\nadmin\nuser\n"

    assert {:ok, valid, []} = CsvLoader.load_string(csv, schema)
    assert length(valid) == 2
    assert hd(valid).role == "admin"
  end

  test "enum type rejects disallowed values" do
    schema = [field("role", type: :enum, values: ["admin", "user", "guest"])]
    csv = "role\nsuperadmin\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    assert {1, "role", msg} = hd(errors)
    assert msg =~ "must be one of"
    assert msg =~ "admin"
    assert msg =~ "user"
    assert msg =~ "guest"
  end

  test "enum type is case-sensitive" do
    schema = [field("role", type: :enum, values: ["admin"])]
    csv = "role\nAdmin\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    assert length(errors) == 1
  end

  # -------------------------------------------------------
  # Default values
  # -------------------------------------------------------

  test "empty optional field with default uses the default" do
    csv = "name,age,score,active,joined\nAlice,30,,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 0.0
  end

  test "empty optional field without default uses nil" do
    schema = [field("note", required: false)]
    csv = "note\n\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.note == nil
  end

  # -------------------------------------------------------
  # Required field validation
  # -------------------------------------------------------

  test "required field that is empty produces an error" do
    csv = "name,age,active,joined\n,30,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "required field that is whitespace-only produces an error" do
    csv = "name,age,active,joined\n   ,30,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  # -------------------------------------------------------
  # Type errors
  # -------------------------------------------------------

  test "invalid integer produces a type error" do
    csv = "name,age,active,joined\nAlice,notanumber,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end

  test "invalid float produces a type error" do
    csv = "name,age,score,active,joined\nAlice,30,notfloat,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "score", msg} = find_error(errors, 1, "score")
    assert msg =~ "float"
  end

  test "invalid boolean produces a type error" do
    csv = "name,age,active,joined\nAlice,30,yes,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end

  # -------------------------------------------------------
  # Format validation
  # -------------------------------------------------------

  test "format check is applied before type coercion" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]

    csv = "code\nABC-123\nabc-123\n"
    assert {:ok, valid, errors} = CsvLoader.load_string(csv, schema)
    assert length(valid) == 1
    assert length(errors) == 1
    assert hd(valid).code == "ABC-123"
  end

  # -------------------------------------------------------
  # Multiple errors
  # -------------------------------------------------------

  test "a single field can produce multiple errors" do
    schema = [field("code", format: ~r/^[A-Z]+$/), field("value")]
    csv = "code,value\n,hello\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    code_errors = Enum.filter(errors, fn {_row, f, _msg} -> f == "code" end)
    assert length(code_errors) >= 1
  end

  test "multiple rows can each have different errors" do
    csv = """
    name,age,active,joined
    ,notnum,yes,bad-date
    Alice,30,true,2024-01-01
    ,abc,2,also-bad
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 1
    assert hd(valid).name == "Alice"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 3
    assert length(row3_errors) >= 2
  end

  # -------------------------------------------------------
  # Row number correctness
  # -------------------------------------------------------

  test "row numbers are 1-based for data rows" do
    csv = """
    name,age,active,joined
    Alice,30,true,2024-01-01
    ,bad,notbool,bad-date
    Bob,25,false,2023-06-01
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 2
    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end

  # -------------------------------------------------------
  # Missing / extra columns
  # -------------------------------------------------------

  test "row with fewer columns treats missing as empty" do
    csv = "name,age,active,joined\nAlice,30\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert find_error(errors, 1, "active") != nil
    assert find_error(errors, 1, "joined") != nil
  end

  test "row with extra columns silently ignores extras" do
    csv = "name,age,active,joined\nAlice,30,true,2024-01-01,extra1,extra2\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.name == "Alice"
    assert map_size(row) == 4
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty string returns error" do
    assert {:error, :empty_file} = CsvLoader.load_string("", @basic_schema)
  end

  test "header-only file returns ok with empty lists" do
    csv = "name,age,active,joined\n"
    assert {:ok, [], []} = CsvLoader.load_string(csv, @basic_schema)
  end

  test "BOM characters are stripped" do
    csv = "\xEF\xBB\xBFname,age,active,joined\nAlice,30,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert Map.has_key?(row, :name)
    assert row.name == "Alice"
  end

  test "whitespace around values is trimmed" do
    csv = "name,age,active,joined\n  Alice  , 30 , true , 2024-01-01 \n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.name == "Alice"
    assert row.age == 30
  end

  test "quoted fields with commas are handled" do
    schema = [field("name"), field("note", required: false)]
    csv = ~s(name,note\n"Smith, John","Has a comma, inside"\n)
    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.name == "Smith, John"
  end

  # -------------------------------------------------------
  # File path functionality
  # -------------------------------------------------------

  test "load_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             CsvLoader.load_file("/tmp/does_not_exist_#{:rand.uniform(999_999)}.csv", @basic_schema)
  end

  test "load_file reads and validates a real file" do
    path = "/tmp/csv_loader_test_#{:rand.uniform(999_999)}.csv"

    content = """
    name,age,active,joined
    Alice,30,true,2024-01-01
    ,bad,nope,bad
    """

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = CsvLoader.load_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 3
  end

  test "load_file handles empty file" do
    path = "/tmp/csv_loader_empty_#{:rand.uniform(999_999)}.csv"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)
    assert {:error, :empty_file} = CsvLoader.load_file(path, @basic_schema)
  end

  # -------------------------------------------------------
  # All-optional schema
  # -------------------------------------------------------

  test "all-optional schema with empty values and defaults" do
    schema = [
      field("a", required: false, default: "none"),
      field("b", required: false, type: :integer, default: 0)
    ]

    csv = "a,b\n,\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.a == "none"
    assert row.b == 0
  end

  # -------------------------------------------------------
  # Large dataset
  # -------------------------------------------------------

  test "handles 500 rows correctly" do
    schema = [field("id", type: :integer), field("val")]
    header = "id,val"

    rows =
      Enum.map(1..500, fn i ->
        if rem(i, 50) == 0, do: "bad,row#{i}", else: "#{i},row#{i}"
      end)

    csv = Enum.join([header | rows], "\n")

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, schema)
    assert length(valid) == 490
    assert length(errors) == 10

    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.sort()
    assert error_rows == Enum.map(1..10, &(&1 * 50))
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp find_error(errors, row, field_name) do
    Enum.find(errors, fn {r, f, _msg} -> r == row and f == field_name end)
  end
end
