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