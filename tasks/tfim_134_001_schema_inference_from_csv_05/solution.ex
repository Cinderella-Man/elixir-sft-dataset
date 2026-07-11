  test "a column of all floats is float, including whole-number floats" do
    csv = """
    ratio
    2.0
    0.5
    100.25
    """

    assert schema(csv) == %{"ratio" => :float}
  end