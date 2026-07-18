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