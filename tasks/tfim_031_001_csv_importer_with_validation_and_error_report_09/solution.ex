  test "float field accepts integer-formatted strings" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,42,true
    """

    assert {:ok, [_], []} = CsvImporter.import_string(csv, @basic_schema)
  end