  test "required field that is whitespace-only produces an error" do
    csv = "name,age,active,joined\n   ,30,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "name", msg} = find_error(errors, 1, "name")
    assert msg =~ "required"
  end