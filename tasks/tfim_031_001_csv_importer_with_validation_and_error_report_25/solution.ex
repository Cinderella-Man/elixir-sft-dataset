  test "quoted fields with commas are handled correctly" do
    schema = [field("name"), field("note", required: false)]

    csv = """
    name,note
    "Smith, John","Has a comma, inside"
    """

    assert {:ok, [row], []} = CsvImporter.import_string(csv, schema)
    assert row["name"] == "Smith, John"
    assert row["note"] == "Has a comma, inside"
  end