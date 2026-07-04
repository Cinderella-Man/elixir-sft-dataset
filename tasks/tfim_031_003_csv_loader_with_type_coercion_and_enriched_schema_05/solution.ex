  test "integer coercion" do
    csv = "name,age,active,joined\nAlice,30,true,2024-01-01\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, @basic_schema)
    assert row.age == 30
    assert is_integer(row.age)
  end