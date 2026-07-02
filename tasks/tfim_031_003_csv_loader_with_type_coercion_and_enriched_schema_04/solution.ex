  test "custom :key option overrides the atom key" do
    schema = [
      field("Full Name", key: :full_name),
      field("age", type: :integer)
    ]

    csv = """
    Full Name,age
    Alice Smith,30
    """

    assert {:ok, [row], []} = CsvLoader.load_string(csv, schema)
    assert row.full_name == "Alice Smith"
  end