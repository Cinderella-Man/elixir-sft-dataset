  test "signed integers and floats are recognized" do
    csv = """
    i,f
    -5,-0.5
    +3,+1.25
    """

    assert schema(csv) == %{"i" => :integer, "f" => :float}
  end