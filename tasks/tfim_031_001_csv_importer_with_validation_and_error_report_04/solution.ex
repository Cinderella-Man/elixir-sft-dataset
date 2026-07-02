  test "required field that is empty produces an error" do
    csv = """
    name,email,age,active
    ,alice@example.com,30,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end