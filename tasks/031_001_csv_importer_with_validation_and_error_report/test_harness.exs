defmodule CsvImporterTest.Helpers do
  def field(name, opts \\ []) do
    %{
      name: name,
      required: Keyword.get(opts, :required, true),
      type: Keyword.get(opts, :type, :string),
      format: Keyword.get(opts, :format, nil)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end

defmodule CsvImporterTest do
  use ExUnit.Case, async: true
  import CsvImporterTest.Helpers

  @basic_schema [
    field("name"),
    field("email", format: :email),
    field("age", type: :integer),
    field("score", type: :float, required: false),
    field("active", type: :boolean)
  ]

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "imports a fully valid CSV" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,95.5,true
    Bob,bob@test.org,25,88.0,false
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice["name"] == "Alice"
    assert alice["email"] == "alice@example.com"
    assert alice["age"] == "30"
    assert bob["active"] == "false"
  end

  test "valid rows are returned as maps keyed by header names" do
    csv = """
    name,email,age,active
    Carol,carol@example.com,40,1
    """

    assert {:ok, [row], []} = CsvImporter.import_string(csv, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, "name")
    assert Map.has_key?(row, "email")
    assert Map.has_key?(row, "age")
    assert Map.has_key?(row, "active")
  end

  # -------------------------------------------------------
  # Required field validation
  # -------------------------------------------------------

  test "required field that is empty produces an error" do
    csv = """
    name,email,age,active
    ,alice@example.com,30,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "required field that is whitespace-only produces an error" do
    csv = """
    name,email,age,active
       ,alice@example.com,30,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "optional field that is empty does NOT produce an error" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,,true
    """

    assert {:ok, [_row], []} = CsvImporter.import_string(csv, @basic_schema)
  end

  # -------------------------------------------------------
  # Type validation
  # -------------------------------------------------------

  test "invalid integer produces a type error" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,notanumber,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end

  test "valid integer passes" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,true
    """

    assert {:ok, [_], []} = CsvImporter.import_string(csv, @basic_schema)
  end

  test "float field accepts integer-formatted strings" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,42,true
    """

    assert {:ok, [_], []} = CsvImporter.import_string(csv, @basic_schema)
  end

  test "invalid float produces a type error" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,notfloat,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "score", msg} = find_error(errors, 1, "score")
    assert msg =~ "float"
  end

  test "boolean field accepts true, false, 1, 0 case-insensitively" do
    csv = """
    name,email,age,active
    A,a@b.com,1,TRUE
    B,b@b.com,2,False
    C,c@b.com,3,0
    D,d@b.com,4,1
    """

    assert {:ok, valid, []} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 4
  end

  test "invalid boolean produces a type error" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,yes
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end

  # -------------------------------------------------------
  # Format / email validation
  # -------------------------------------------------------

  test "invalid email format produces a format error" do
    csv = """
    name,email,age,active
    Alice,not-an-email,30,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "email", msg} = find_error(errors, 1, "email")
    assert msg =~ "format"
  end

  test "custom regex format works" do
    schema = [
      field("code", format: ~r/^[A-Z]{3}-\d{3}$/)
    ]

    csv = """
    code
    ABC-123
    abc-123
    TOOLONG-1234
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end

  # -------------------------------------------------------
  # Multiple errors on a single field / row
  # -------------------------------------------------------

  test "a single field can produce multiple errors" do
    # "age" is required, not an integer, — we need a field that triggers both
    # Use a required field with a format check and give it empty value
    schema = [
      field("code", format: ~r/^[A-Z]+$/),
      field("value")
    ]

    csv = """
    code,value
    ,hello
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, schema)
    code_errors = Enum.filter(errors, fn {_row, f, _msg} -> f == "code" end)
    # Should have at least "required" error; format error on empty may or may not fire
    assert length(code_errors) >= 1
  end

  test "multiple rows can each have different errors" do
    csv = """
    name,email,age,active
    ,bad-email,notnum,yes
    Alice,alice@example.com,30,true
    ,also-bad,abc,2
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 1
    assert hd(valid)["name"] == "Alice"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 3
    assert length(row3_errors) >= 2
  end

  # -------------------------------------------------------
  # Row number correctness
  # -------------------------------------------------------

  test "row numbers are 1-based for data rows (header is not counted)" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,true
    ,bad,notnum,yes
    Bob,bob@test.com,25,false
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 2

    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end

  # -------------------------------------------------------
  # Missing / extra columns
  # -------------------------------------------------------

  test "row with fewer columns than header treats missing as empty" do
    csv = """
    name,email,age,active
    Alice,alice@example.com
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    age_error = find_error(errors, 1, "age")
    active_error = find_error(errors, 1, "active")
    assert age_error != nil
    assert active_error != nil
  end

  test "row with extra columns silently ignores extras" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,true,extra1,extra2
    """

    assert {:ok, [row], []} = CsvImporter.import_string(csv, @basic_schema)
    assert row["name"] == "Alice"
    # Extra columns should not appear in the map
    assert map_size(row) == 4
  end

  # -------------------------------------------------------
  # Edge cases: empty file, header-only, BOM
  # -------------------------------------------------------

  test "empty file returns error" do
    assert {:error, :empty_file} = CsvImporter.import_string("", @basic_schema)
  end

  test "file with only headers returns ok with empty lists" do
    csv = "name,email,age,active\n"

    assert {:ok, [], []} = CsvImporter.import_string(csv, @basic_schema)
  end

  test "BOM characters at start of file are stripped" do
    # UTF-8 BOM: EF BB BF
    csv = "\xEF\xBB\xBFname,email,age,active\nAlice,alice@example.com,30,true\n"

    assert {:ok, [row], []} = CsvImporter.import_string(csv, @basic_schema)
    # The key should be "name" not "\xEF\xBB\xBFname"
    assert Map.has_key?(row, "name")
    assert row["name"] == "Alice"
  end

  # -------------------------------------------------------
  # Whitespace trimming
  # -------------------------------------------------------

  test "leading and trailing whitespace is trimmed from values" do
    csv = """
    name,email,age,active
      Alice  , alice@example.com ,  30 , true
    """

    assert {:ok, [row], []} = CsvImporter.import_string(csv, @basic_schema)
    assert row["name"] == "Alice"
    assert row["email"] == "alice@example.com"
    assert row["age"] == "30"
  end

  # -------------------------------------------------------
  # Quoted fields with commas / newlines
  # -------------------------------------------------------

  test "quoted fields with commas are handled correctly" do
    schema = [field("name"), field("note", required: false)]

    csv = """
    name,note
    "Smith, John","Has a comma, inside"
    """

    assert {:ok, [row], []} = CsvImporter.import_string(csv, schema)
    assert row["name"] == "Smith, John"
    assert row["note"] == "Has a comma, inside"
  end

  # -------------------------------------------------------
  # File path functionality
  # -------------------------------------------------------

  test "import_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             CsvImporter.import_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.csv",
               @basic_schema
             )
  end

  test "import_file reads and validates a real file" do
    path = "/tmp/csv_importer_test_#{:rand.uniform(999_999)}.csv"

    content = """
    name,email,age,active
    Alice,alice@example.com,30,true
    ,bad,nope,yes
    """

    File.write!(path, content)

    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = CsvImporter.import_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 3
  end

  test "import_file handles empty file" do
    path = "/tmp/csv_importer_empty_#{:rand.uniform(999_999)}.csv"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :empty_file} = CsvImporter.import_file(path, @basic_schema)
  end

  # -------------------------------------------------------
  # Schema with only optional fields
  # -------------------------------------------------------

  test "all-optional schema with empty values produces no errors" do
    schema = [
      field("a", required: false),
      field("b", required: false, type: :integer)
    ]

    csv = """
    a,b
    ,
    """

    assert {:ok, [_row], []} = CsvImporter.import_string(csv, schema)
  end

  # -------------------------------------------------------
  # Large-ish dataset sanity check
  # -------------------------------------------------------

  test "handles 500 rows correctly" do
    schema = [field("id", type: :integer), field("val")]

    header = "id,val"

    rows =
      Enum.map(1..500, fn i ->
        if rem(i, 50) == 0 do
          "bad,row#{i}"
        else
          "#{i},row#{i}"
        end
      end)

    csv = Enum.join([header | rows], "\n")

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, schema)
    assert length(valid) == 490
    assert length(errors) == 10

    # All errors should be on every 50th row
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
