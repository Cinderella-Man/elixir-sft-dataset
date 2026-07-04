  test "float coercion from decimal string" do
    csv = "name,age,score,active,joined\nAlice,30,3.14,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 3.14
    assert is_float(row.score)
  end