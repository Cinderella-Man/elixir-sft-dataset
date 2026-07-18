  test "signed numerics classify per the documented regexes, partial decimals do not" do
    csv = """
    i,f,x
    +5,+1.5,1.
    -3,-2.25,.5
    """

    assert schema(csv) == %{"i" => :integer, "f" => :float, "x" => :string}
  end