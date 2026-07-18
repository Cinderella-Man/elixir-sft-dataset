  test "enum type is case-sensitive" do
    schema = [field("role", type: :enum, values: ["admin"])]
    csv = "role\nAdmin\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    assert length(errors) == 1
  end