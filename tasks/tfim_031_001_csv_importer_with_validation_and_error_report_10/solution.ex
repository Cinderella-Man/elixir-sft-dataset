  test "invalid float produces a type error" do
    csv = """
    name,email,age,score,active
    Alice,alice@example.com,30,notfloat,true
    """

    assert {:ok, [], errors} = CsvImporter.import_string(csv, @basic_schema)
    assert {1, "score", msg} = find_error(errors, 1, "score")
    assert msg =~ "float"
  end