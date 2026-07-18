  test "file with only headers returns ok with empty lists" do
    csv = "name,email,age,active\n"

    assert {:ok, [], []} = CsvImporter.import_string(csv, @basic_schema)
  end