  test "a column of pure dates in multiple formats stays date" do
    csv = """
    d
    2020-01-15
    03/25/2021
    """

    assert schema(csv) == %{"d" => :date}
  end