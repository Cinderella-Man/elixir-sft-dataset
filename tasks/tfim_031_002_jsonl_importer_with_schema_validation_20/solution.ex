  test "non-object JSON (array) produces an invalid JSON error" do
    jsonl = ~s([1, 2, 3]\n)

    assert {:ok, [], errors} = JsonlImporter.import_string(jsonl, @basic_schema)
    assert {1, "_line", msg} = hd(errors)
    assert msg =~ "invalid JSON"
  end