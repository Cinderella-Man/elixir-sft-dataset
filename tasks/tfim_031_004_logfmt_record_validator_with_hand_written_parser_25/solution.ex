  test "line numbers are 1-based and skip blank lines" do
    input = """
    level=info host=web01 method=GET duration=42 success=true

    host=web02 method=POST duration=bad success=yes

    level=warn host=web03 method=PUT duration=10 success=false
    """

    assert {:ok, valid, errors} = LogfmtValidator.validate_string(input, @basic_schema)
    assert length(valid) == 2

    error_rows = Enum.map(errors, fn {row, _f, _m} -> row end) |> Enum.uniq()
    assert error_rows == [2]
  end