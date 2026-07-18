  test "multiple rows can each have different errors" do
    csv = """
    name,email,age,active
    ,bad-email,notnum,yes
    Alice,alice@example.com,30,true
    ,also-bad,abc,2
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, @basic_schema)
    assert length(valid) == 1
    assert hd(valid)["name"] == "Alice"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 3
    assert length(row3_errors) >= 2
  end