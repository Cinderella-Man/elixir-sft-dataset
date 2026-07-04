  test "valid integer passes" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,true
    """

    assert {:ok, [_], []} = CsvImporter.import_string(csv, @basic_schema)
  end