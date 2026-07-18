  test "invalid float produces a type error" do
    csv = "name,age,score,active,joined\nAlice,30,notfloat,true,2024-01-01\n"
    assert {:ok, [], errors} = CsvLoader.load_string(csv, @basic_schema)
    assert {1, "score", msg} = find_error(errors, 1, "score")
    assert msg =~ "float"
  end