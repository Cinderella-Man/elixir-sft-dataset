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