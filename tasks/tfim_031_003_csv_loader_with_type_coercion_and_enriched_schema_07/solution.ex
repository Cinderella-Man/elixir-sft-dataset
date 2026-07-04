  test "float coercion from integer string" do
    csv = "name,age,score,active,joined\nAlice,30,42,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.score == 42.0
    assert is_float(row.score)
  end