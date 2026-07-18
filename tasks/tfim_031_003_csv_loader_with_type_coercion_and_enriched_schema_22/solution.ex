  test "format check is applied before type coercion" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]

    csv = "code\nABC-123\nabc-123\n"
    assert {:ok, valid, errors} = CsvLoader.load_string(csv, schema)
    assert length(valid) == 1
    assert length(errors) == 1
    assert hd(valid).code == "ABC-123"
  end