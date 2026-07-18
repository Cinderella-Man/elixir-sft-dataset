  test "a single field can produce multiple errors" do
    schema = [field("code", format: ~r/^[A-Z]+$/), field("value")]
    csv = "code,value\n,hello\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    code_errors = Enum.filter(errors, fn {_row, f, _msg} -> f == "code" end)
    assert length(code_errors) >= 1
  end