defmodule LogfmtValidatorTest.Helpers do
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

defmodule LogfmtValidatorTest do
  use ExUnit.Case, async: true
  import LogfmtValidatorTest.Helpers

  @basic_schema [
    field("level"),
    field("host"),
    field("method"),
    field("duration", type: :integer),
    field("success", type: :boolean)
  ]

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "validates fully valid logfmt records" do
    input = """
    level=info host=web01 method=GET duration=42 success=true
    level=error host=web02 method=POST duration=150 success=false
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 2
    assert errors == []

    [first, second] = valid
    assert first["level"] == "info"
    assert first["host"] == "web01"
    assert first["duration"] == "42"
    assert second["success"] == "false"
  end

  test "valid records are returned as maps keyed by field names" do
    input = "level=info host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert is_map(row)
    assert Map.has_key?(row, "level")
    assert Map.has_key?(row, "host")
    assert Map.has_key?(row, "method")
    assert Map.has_key?(row, "duration")
    assert Map.has_key?(row, "success")
  end

  # -------------------------------------------------------
  # Logfmt parsing features
  # -------------------------------------------------------

  test "quoted values with spaces are parsed correctly" do
    schema = [field("msg"), field("level")]
    input = ~s(level=info msg="hello world"\n)

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == "hello world"
  end

  test "quoted values with escaped quotes are parsed correctly" do
    schema = [field("msg")]
    input = ~s(msg="he said \\"hi\\""\n)

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == ~s(he said "hi")
  end

  test "bare keys (no = sign) are treated as boolean flags with value true" do
    schema = [field("verbose", type: :boolean), field("level")]
    input = "verbose level=info\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["verbose"] == "true"
  end

  test "key with = but empty value produces empty string" do
    schema = [field("msg", required: false), field("level")]
    input = "level=info msg=\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["msg"] == ""
  end

  test "duplicate keys — last occurrence wins" do
    schema = [field("level")]
    input = "level=info level=error\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["level"] == "error"
  end

  test "unterminated quote produces a malformed line error" do
    input = ~s(level=info msg="unterminated\n)

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "_line", msg} = hd(errors)
    assert msg =~ "malformed"
  end

  # -------------------------------------------------------
  # Required field validation
  # -------------------------------------------------------

  test "required field that is missing produces an error" do
    input = "host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "level", msg} = find_error(errors, 1, "level")
    assert msg =~ "required"
  end

  test "required field with empty value produces an error" do
    input = "level= host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "level", msg} = find_error(errors, 1, "level")
    assert msg =~ "required"
  end

  test "optional field that is missing does NOT produce an error" do
    schema = [field("level"), field("tag", required: false)]
    input = "level=info\n"

    assert {:ok, [_row], []} = LogfmtValidator.validate_string(input, schema)
  end

  # -------------------------------------------------------
  # Type validation
  # -------------------------------------------------------

  test "invalid integer produces a type error" do
    input = "level=info host=web01 method=GET duration=abc success=true\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "duration", msg} = find_error(errors, 1, "duration")
    assert msg =~ "integer"
  end

  test "valid integer passes" do
    input = "level=info host=web01 method=GET duration=42 success=true\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, @basic_schema)
  end

  test "float field accepts integer-formatted strings" do
    schema = [field("latency", type: :float)]
    input = "latency=42\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, schema)
  end

  test "float field accepts decimal strings" do
    schema = [field("latency", type: :float)]
    input = "latency=3.14\n"
    assert {:ok, [_], []} = LogfmtValidator.validate_string(input, schema)
  end

  test "invalid float produces a type error" do
    schema = [field("latency", type: :float)]
    input = "latency=notfloat\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, schema)
    assert {1, "latency", msg} = hd(errors)
    assert msg =~ "float"
  end

  test "boolean field accepts true, false, 1, 0 case-insensitively" do
    schema = [field("flag", type: :boolean)]

    lines = ["flag=TRUE", "flag=False", "flag=0", "flag=1"]
    input = Enum.join(lines, "\n")

    assert {:ok, valid, []} = LogfmtValidator.validate_string(input, schema)
    assert length(valid) == 4
  end

  test "invalid boolean produces a type error" do
    input = "level=info host=web01 method=GET duration=42 success=yes\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert {1, "success", msg} = find_error(errors, 1, "success")
    assert msg =~ "boolean"
  end

  # -------------------------------------------------------
  # Format / IPv4 validation
  # -------------------------------------------------------

  test "ipv4 format accepts valid addresses" do
    schema = [field("ip", format: :ipv4)]
    input = "ip=192.168.1.1\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, schema)
    assert row["ip"] == "192.168.1.1"
  end

  test "ipv4 format rejects invalid addresses" do
    schema = [field("ip", format: :ipv4)]
    input = "ip=999.999.999.999\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, schema)
    assert {1, "ip", msg} = hd(errors)
    assert msg =~ "format"
  end

  test "custom regex format works" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]
    input = "code=ABC-123\ncode=abc-123\ncode=TOOLONG-1234\n"

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end

  # -------------------------------------------------------
  # Multiple errors
  # -------------------------------------------------------

  test "a single record can produce multiple errors" do
    # missing level, bad duration, bad success
    input = "host=web01 method=GET duration=abc success=yes\n"

    assert {:ok, [], errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(errors) >= 3
  end

  test "multiple records can each have different errors" do
    input = """
    host=web01 method=GET duration=abc success=yes
    level=info host=web01 method=GET duration=42 success=true
    method=POST duration=bad success=0
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 1
    assert hd(valid)["level"] == "info"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 2
    assert length(row3_errors) >= 2
  end

  # -------------------------------------------------------
  # Line number correctness (blank lines skipped)
  # -------------------------------------------------------

  test "line numbers are 1-based and skip blank lines" do
    input = """
    level=info host=web01 method=GET duration=42 success=true

    host=web02 method=POST duration=bad success=yes

    level=warn host=web03 method=PUT duration=10 success=false
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 2

    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end

  # -------------------------------------------------------
  # Extra keys are ignored
  # -------------------------------------------------------

  test "extra keys not in schema are silently ignored" do
    input = "level=info host=web01 method=GET duration=42 success=true extra=stuff another=42\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert row["level"] == "info"
    refute Map.has_key?(row, "extra")
    refute Map.has_key?(row, "another")
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "empty string returns error" do
    assert {:error, :empty_file} = LogfmtValidator.validate_string("", @basic_schema)
  end

  test "string with only blank lines returns error" do
    assert {:error, :empty_file} = LogfmtValidator.validate_string("\n\n  \n", @basic_schema)
  end

  test "BOM characters at start are stripped" do
    input = "\xEF\xBB\xBF" <> "level=info host=web01 method=GET duration=42 success=true\n"

    assert {:ok, [row], []} = LogfmtValidator.validate_string(input, @basic_schema)
    assert row["level"] == "info"
  end

  # -------------------------------------------------------
  # File path functionality
  # -------------------------------------------------------

  test "validate_file returns error for nonexistent file" do
    assert {:error, :file_not_found} =
             LogfmtValidator.validate_file(
               "/tmp/does_not_exist_#{:rand.uniform(999_999)}.log",
               @basic_schema
             )
  end

  test "validate_file reads and validates a real file" do
    path = "/tmp/logfmt_test_#{:rand.uniform(999_999)}.log"

    content = """
    level=info host=web01 method=GET duration=42 success=true
    host=web02 duration=bad success=yes
    """

    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, valid, errors} = LogfmtValidator.validate_file(path, @basic_schema)
    assert length(valid) == 1
    assert length(errors) >= 2
  end

  test "validate_file handles empty file" do
    path = "/tmp/logfmt_empty_#{:rand.uniform(999_999)}.log"
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:error, :empty_file} = LogfmtValidator.validate_file(path, @basic_schema)
  end

  # -------------------------------------------------------
  # All-optional schema
  # -------------------------------------------------------

  test "all-optional schema with missing keys produces no errors" do
    schema = [
      field("a", required: false),
      field("b", required: false, type: :integer)
    ]

    input = "unrelated=stuff\n"

    assert {:ok, [_row], []} = LogfmtValidator.validate_string(input, schema)
  end

  # -------------------------------------------------------
  # Large dataset
  # -------------------------------------------------------

  test "handles 500 records correctly" do
    schema = [field("id", type: :integer), field("val")]

    lines =
      Enum.map(1..500, fn i ->
        if rem(i, 50) == 0 do
          "id=bad val=row#{i}"
        else
          "id=#{i} val=row#{i}"
        end
      end)

    input = Enum.join(lines, "\n")

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, schema)
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
