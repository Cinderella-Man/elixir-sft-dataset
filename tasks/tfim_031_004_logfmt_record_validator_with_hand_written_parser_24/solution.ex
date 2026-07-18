  test "multiple records can each have different errors" do
    input = """
    host=web01 method=GET duration=abc success=yes
    level=info host=web01 method=GET duration=42 success=true
    method=POST duration=bad success=0
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 1
    assert hd(valid)["level"] == "info"

    row1_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 1 end)
    row3_errors = Enum.filter(errors, fn {row, _f, _m} -> row == 3 end)

    assert length(row1_errors) >= 2
    assert length(row3_errors) >= 2
  end