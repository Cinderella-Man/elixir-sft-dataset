  test "custom regex format works" do
    schema = [
      field("code", format: ~r/^[A-Z]{3}-\d{3}$/)
    ]

    csv = """
    code
    ABC-123
    abc-123
    TOOLONG-1234
    """

    assert {:ok, valid, errors} = CsvImporter.import_string(csv, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end