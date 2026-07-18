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