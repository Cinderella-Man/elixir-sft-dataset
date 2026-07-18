  test "row with extra columns silently ignores extras" do
    csv = "name,age,active,joined\nAlice,30,true,2024-01-01,extra1,extra2\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.name == "Alice"
    assert map_size(row) == 4
  end