  test "empty optional field without default uses nil" do
    schema = [field("note", required: false)]
    csv = "note\n\n"
    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.note == nil
  end