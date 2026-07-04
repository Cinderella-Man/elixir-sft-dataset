  test "invalid date produces a type error" do
    csv = "name,age,active,joined\nAlice,30,true,not-a-date\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "joined", msg} = find_error(errors, 1, "joined")
    assert msg =~ "date"
  end