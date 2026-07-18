  test "invalid email format produces a format error" do
    csv = """
    name,email,age,active
    Alice,not-an-email,30,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "email", msg} = find_error(errors, 1, "email")
    assert msg =~ "format"
  end