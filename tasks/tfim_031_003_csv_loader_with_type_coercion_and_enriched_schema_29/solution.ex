  test "header-only file returns ok with empty lists" do
    csv = "name,age,active,joined\n"
    assert {:ok, [], []} = CsvLoader.load_string(csv, @basic_schema)
  end