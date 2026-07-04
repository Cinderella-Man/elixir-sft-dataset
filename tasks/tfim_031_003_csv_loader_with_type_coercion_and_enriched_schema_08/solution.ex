  test "boolean coercion accepts true/false/1/0 case-insensitively" do
    csv = """
    name,age,active,joined
    A,1,TRUE,2024-01-01
    B,2,False,2024-01-01
    C,3,0,2024-01-01
    D,4,1,2024-01-01
    """

    assert {:ok, valid, []} = CsvLoader.load_string(csv, @basic_schema)
    assert Enum.map(valid, & &1.active) == [true, false, false, true]
  end