  test "cross-family mixes still widen to the string top" do
    csv = """
    a,b,c
    1,2020-01-15,true
    2020-01-15T10:00:00,5,7
    """

    # a: integer + datetime -> string
    # b: date + integer -> string
    # c: boolean + integer -> string
    assert schema(csv) == %{"a" => :string, "b" => :string, "c" => :string}
  end