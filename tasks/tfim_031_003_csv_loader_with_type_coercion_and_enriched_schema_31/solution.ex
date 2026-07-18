  test "whitespace around values is trimmed" do
    csv = "name,age,active,joined\n  Alice  , 30 , true , 2024-01-01 \n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.name == "Alice"
    assert row.age == 30
  end