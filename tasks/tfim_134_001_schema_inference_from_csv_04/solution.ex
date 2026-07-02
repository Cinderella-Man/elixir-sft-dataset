  test "a column that is all integers except one float is a float" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => :float}
  end