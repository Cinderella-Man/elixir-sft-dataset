  test "BOM characters at start of file are stripped" do
    # UTF-8 BOM: EF BB BF
    csv = "\xEF\xBB\xBFname,email,age,active\nAlice,alice@example.com,30,true\n"

    assert {:ok, [row], []} = CsvImporter.import_string(csv, @basic_schema)
    # The key should be "name" not "\xEF\xBB\xBFname"
    assert Map.has_key?(row, "name")
    assert row["name"] == "Alice"
  end