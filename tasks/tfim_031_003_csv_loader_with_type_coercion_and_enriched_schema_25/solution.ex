  test "row numbers are 1-based for data rows" do
    csv = """
    name,age,active,joined
    Alice,30,true,2024-01-01
    ,bad,notbool,bad-date
    Bob,25,false,2023-06-01
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 2
    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end