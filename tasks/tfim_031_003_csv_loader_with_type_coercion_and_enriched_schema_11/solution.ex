  test "date with invalid calendar date produces an error" do
    csv = "name,age,active,joined\nAlice,30,true,2024-02-30\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert find_error(errors, 1, "joined") != nil
  end