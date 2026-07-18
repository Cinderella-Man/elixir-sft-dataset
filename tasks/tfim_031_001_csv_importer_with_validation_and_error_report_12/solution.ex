  test "invalid boolean produces a type error" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,yes
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "active", msg} = find_error(errors, 1, "active")
    assert msg =~ "boolean"
  end