  test "invalid integer produces a type error" do
    csv = "name,age,active,joined\nAlice,notanumber,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end