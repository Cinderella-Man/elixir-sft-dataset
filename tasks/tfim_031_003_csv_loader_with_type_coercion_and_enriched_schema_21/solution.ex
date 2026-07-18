  test "invalid boolean produces a type error" do
    csv = "name,age,active,joined\nAlice,30,yes,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end