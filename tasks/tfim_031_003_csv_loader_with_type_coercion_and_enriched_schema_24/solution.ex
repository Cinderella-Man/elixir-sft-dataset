  test "multiple rows can each have different errors" do
    csv = """
    name,age,active,joined
    ,notnum,yes,bad-date
    Alice,30,true,2024-01-01
    ,abc,2,also-bad
    """

    assert {:ok, valid, errors} = CsvLoader.load_string(csv, @basic_schema)
    assert length(valid) == 1
    assert hd(valid).name == "Alice"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 3
    assert length(row3_errors) >= 2
  end