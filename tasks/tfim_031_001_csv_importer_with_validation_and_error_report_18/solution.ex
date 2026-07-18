  test "row numbers are 1-based for data rows (header is not counted)" do
    csv = """
    name,email,age,active
    Alice,alice@example.com,30,true
    ,bad,notnum,yes
    Bob,bob@test.com,25,false
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 2

    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end