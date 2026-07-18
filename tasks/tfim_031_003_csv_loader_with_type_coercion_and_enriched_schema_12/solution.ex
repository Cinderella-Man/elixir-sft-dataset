  test "enum type accepts allowed values" do
    schema = [field("role", type: :enum, values: ["admin", "user", "guest"])]
    csv = "role\nadmin\nuser\n"

    assert {:ok, valid, []} = CsvLoader.load_string(csv, schema)
    assert length(valid) == 2
    assert hd(valid).role == "admin"
  end