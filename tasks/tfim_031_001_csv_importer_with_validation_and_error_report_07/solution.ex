  test "invalid integer produces a type error" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,notanumber,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "age", msg} = find_error(errors, 1, "age")
    assert msg =~ "integer"
  end