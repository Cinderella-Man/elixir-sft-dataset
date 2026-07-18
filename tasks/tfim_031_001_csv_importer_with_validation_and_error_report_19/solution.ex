  test "row with fewer columns than header treats missing as empty" do
    csv = """
    name,email,age,active
    Alice,alice@example.com
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    age_error = find_error(errors, 1, "age")
    active_error = find_error(errors, 1, "active")
    assert age_error != nil
    assert active_error != nil
  end