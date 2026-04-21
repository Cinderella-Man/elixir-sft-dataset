defmodule JsonlImporterTest.Helpers do
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

defmodule JsonlImporterTest do
  use ExUnit.Case, async: true
  import JsonlImporterTest.Helpers

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

  test "imports fully valid JSONL" do
    jsonl = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "score": 95.5, "active": true}
    {"name": "Bob", "email": "bob@test.org", "age": 25, "score": 88.0, "active": false}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [alice, bob] = valid
    assert alice["name"] == "Alice"
    assert alice["email"] == "alice@example.com"
    assert alice["age"] == 30
    assert bob["active"] == false
  end

  test "valid records are returned as maps keyed by field names" do
    jsonl = ~s({"name": "Carol", "email": "carol@example.com", "age": 40, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, "name")
    assert Map.has_key?(row, "email")
    assert Map.has_key?(row, "age")
    assert Map.has_key?(row, "active")
  end

  # -------------------------------------------------------
  # Required field validation
  # -------------------------------------------------------

  test "required field that is null produces an error" do
    jsonl = ~s({"name": null, "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "required field that is missing from JSON produces an error" do
    jsonl = ~s({"email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "required string field that is whitespace-only produces an error" do
    jsonl = ~s({"name": "   ", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end

  test "optional field that is null does NOT produce an error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "score": null, "active": true}\n)

    assert {:ok, [_row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end

  test "optional field that is missing does NOT produce an error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [_row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end

  # -------------------------------------------------------
  # Type validation
  # -------------------------------------------------------

  test "string field with non-string value produces a type error" do
    jsonl = ~s({"name": 123, "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "string"
  end

  test "integer field with float value produces a type error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30.5, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end

  test "integer field with string value produces a type error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": "thirty", "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end

  test "valid integer passes" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end

  test "float field accepts integer values" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "score": 42, "active": true}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end

  test "invalid float produces a type error" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "score": "notfloat", "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "score", msg} = find_error(errors, 1, "score")
    assert msg =~ "float"
  end

  test "boolean field must be actual JSON boolean" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": "true"}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end

  test "valid boolean passes" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": false}\n)

    assert {:ok, [_], []} = JsonlImporter.import_string(jsonl, @basic_schema)
  end

  test "list type validation" do
    schema = [field("tags", type: :list, required: false)]

    jsonl = """
    {"tags": ["a", "b"]}
    {"tags": "not a list"}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, schema)
    assert length(valid) == 1
    assert length(errors) == 1
    assert {2, "tags", msg} = find_error(errors, 2, "tags")
    assert msg =~ "list"
  end

  # -------------------------------------------------------
  # Format / email validation
  # -------------------------------------------------------

  test "invalid email format produces a format error" do
    jsonl = ~s({"name": "Alice", "email": "not-an-email", "age": 30, "active": true}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "email", msg} = find_error(errors, 1, "email")
    assert msg =~ "format"
  end

  test "custom regex format works" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]

    jsonl = """
    {"code": "ABC-123"}
    {"code": "abc-123"}
    {"code": "TOOLONG-1234"}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end

  # -------------------------------------------------------
  # Invalid JSON lines
  # -------------------------------------------------------

  test "malformed JSON produces an invalid JSON error" do
    jsonl = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}
    {this is not valid json}
    {"name": "Bob", "email": "bob@test.org", "age": 25, "active": false}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 2
    assert length(errors) == 1
    assert {2, "_line", msg} = hd(errors)
    assert msg =~ "invalid JSON"
  end

  test "non-object JSON (array) produces an invalid JSON error" do
    jsonl = ~s([1, 2, 3]\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "_line", msg} = hd(errors)
    assert msg =~ "invalid JSON"
  end

  # -------------------------------------------------------
  # Multiple errors on a single record
  # -------------------------------------------------------

  test "a single record can produce multiple errors" do
    jsonl = ~s({"name": null, "email": "bad", "age": "notnum", "active": "yes"}\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    # name: required, email: format, age: type, active: type
    assert length(errors) >= 4
  end

  test "multiple records can each have different errors" do
    jsonl = """
    {"name": null, "email": "bad", "age": "notnum", "active": "yes"}
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}
    {"email": "also-bad", "age": true, "active": 42}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 1
    assert hd(valid)["name"] == "Alice"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 3
    assert length(row3_errors) >= 2
  end

  # -------------------------------------------------------
  # Line number correctness
  # -------------------------------------------------------

  test "line numbers are 1-based and skip blank lines" do
    jsonl = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}

    {"name": null, "email": "bad", "age": 25, "active": false}

    {"name": "Bob", "email": "bob@test.com", "age": 25, "active": false}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert length(valid) == 2

    # The blank lines are skipped; the error is on the 2nd non-blank line
    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end

  # -------------------------------------------------------
  # Extra fields are ignored
  # -------------------------------------------------------

  test "extra fields in JSON object are silently ignored" do
    jsonl = ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true, "extra": "stuff", "another": 42}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert row["name"] == "Alice"
    # Extra fields should not appear in the map
    refute Map.has_key?(row, "extra")
    refute Map.has_key?(row, "another")
  end

  # -------------------------------------------------------
  # Edge cases: empty file, BOM, blank lines
  # -------------------------------------------------------

  test "empty string returns error" do
    assert {:error, :empty_file} = JsonlImporter.import_string("", @basic_schema)
  end

  test "string with only blank lines returns error" do
    assert {:error, :empty_file} = JsonlImporter.import_string("\n\n  \n", @basic_schema)
  end

  test "BOM characters at start of file are stripped" do
    jsonl = "\xEF\xBB\xBF" <> ~s({"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert row["name"] == "Alice"
  end

  # -------------------------------------------------------
  # Whitespace trimming on string values
  # -------------------------------------------------------

  test "leading and trailing whitespace is trimmed from string values" do
    jsonl = ~s({"name": "  Alice  ", "email": " alice@example.com ", "age": 30, "active": true}\n)

    assert {:ok, [row], []} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert row["name"] == "Alice"
    assert row["email"] == "alice@example.com"
  end

  # -------------------------------------------------------
  # File path functionality
  # -------------------------------------------------------

  test "import_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             JsonlImporter.import_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.jsonl",
               @basic_schema
             )
  end

  test "import_file reads and validates a real file" do
    path = "/tmp/jsonl_importer_test_#{:rand.uniform(999_999)}.jsonl"

    content = """
    {"name": "Alice", "email": "alice@example.com", "age": 30, "active": true}
    {"name": null, "email": "bad", "age": "nope", "active": "yes"}
    """

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = JsonlImporter.import_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 3
  end

  test "import_file handles empty file" do
    path = "/tmp/jsonl_importer_empty_#{:rand.uniform(999_999)}.jsonl"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :empty_file} = JsonlImporter.import_file(path, @basic_schema)
  end

  # -------------------------------------------------------
  # Schema with only optional fields
  # -------------------------------------------------------

  test "all-optional schema with null values produces no errors" do
    schema = [
      field("a", required: false),
      field("b", required: false, type: :integer)
    ]

    jsonl = ~s({"a": null, "b": null}\n)

    assert {:ok, [_row], []} = JsonlImporter.import_string(jsonl, schema)
  end

  # -------------------------------------------------------
  # Large-ish dataset sanity check
  # -------------------------------------------------------

  test "handles 500 records correctly" do
    schema = [field("id", type: :integer), field("val")]

    lines =
      Enum.map(1..500, fn i ->
        if rem(i, 50) == 0 do
          ~s({"id": "bad", "val": "row#{i}"})
        else
          ~s({"id": #{i}, "val": "row#{i}"})
        end
      end)

    jsonl = Enum.join(lines, "\n")

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, schema)
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
