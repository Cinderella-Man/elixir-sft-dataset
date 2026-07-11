  test "null cells never affect the join" do
    csv = """
    x
    2020-01-15
    ,
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"x" => :datetime}
  end