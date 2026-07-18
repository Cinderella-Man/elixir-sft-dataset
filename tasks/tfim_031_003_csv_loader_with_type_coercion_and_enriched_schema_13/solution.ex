  test "enum type rejects disallowed values" do
    schema = [field("role", type: :enum, values: ["admin", "user", "guest"])]
    csv = "role\nsuperadmin\n"

    assert {:ok, [], errors} = CsvLoader.load_string(csv, schema)
    assert {1, "role", msg} = hd(errors)
    assert msg =~ "must be one of"
    assert msg =~ "admin"
    assert msg =~ "user"
    assert msg =~ "guest"
  end