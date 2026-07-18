  test "row with fewer columns treats missing as empty" do
    csv = "name,age,active,joined\nAlice,30\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert find_error(errors, 1, "active") != nil
    assert find_error(errors, 1, "joined") != nil
  end