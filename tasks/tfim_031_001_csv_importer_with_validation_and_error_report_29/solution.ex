  test "all-optional schema with empty values produces no errors" do
    schema = [
      field("a", required: false),
      field("b", required: false, type: :integer)
    ]

    csv = """
    a,b
    ,
    """

    assert {:ok, [_row], []} = CsvImporter.import_string(csv, schema)
  end