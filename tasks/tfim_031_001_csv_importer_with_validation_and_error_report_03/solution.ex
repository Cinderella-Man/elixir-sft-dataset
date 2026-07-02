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