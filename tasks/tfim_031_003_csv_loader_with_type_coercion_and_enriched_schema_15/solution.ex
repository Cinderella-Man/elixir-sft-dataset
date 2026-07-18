  test "empty optional field with default uses the default" do
    csv = "name,age,score,active,joined\nAlice,30,,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 0.0
  end