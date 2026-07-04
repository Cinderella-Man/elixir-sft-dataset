  test "optional field that is empty does NOT produce an error" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,,true
    """

    assert {:ok, [_row], []} = CsvImporter.import_string(csv, @basic_schema)
  end