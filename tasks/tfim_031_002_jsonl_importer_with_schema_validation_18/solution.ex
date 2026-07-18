  test "custom regex format works" do
    schema = [field("code", format: ~r/^[A-Z]{3}-\d{3}$/)]

    jsonl = """
    {"code": "ABC-123"}
    {"code": "abc-123"}
    {"code": "TOOLONG-1234"}
    """

    assert {:ok, valid, errors} = JsonlImporter.import_string(jsonl, schema)
    assert length(valid) == 1
    assert length(errors) == 2
    assert hd(valid)["code"] == "ABC-123"
  end