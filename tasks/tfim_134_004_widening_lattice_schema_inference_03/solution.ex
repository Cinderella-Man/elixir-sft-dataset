  test "numeric widening: integers plus a float become float" do
    csv = """
    val
    1
    2
    3.5
    """

    assert schema(csv) == %{"val" => :float}
  end