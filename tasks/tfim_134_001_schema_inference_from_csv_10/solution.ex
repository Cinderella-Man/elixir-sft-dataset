  test "null cells are ignored within an otherwise-typed column" do
    csv = """
    a,b
    1,x
    ,y
    3,z
    """

    assert schema(csv) == %{"a" => :integer, "b" => :string}
  end