  test "a header row with no data rows yields all-string columns" do
    csv = """
    a,b,c
    """

    assert schema(csv) == %{"a" => :string, "b" => :string, "c" => :string}
  end