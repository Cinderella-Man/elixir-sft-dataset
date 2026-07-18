  test "BOM characters are stripped" do
    csv = "\xEF\xBB\xBFname,age,active,joined\nAlice,30,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert Map.has_key?(row, :name)
    assert row.name == "Alice"
  end