  test "invalid calendar dates fall back to string and drag the column to string" do
    csv = """
    d
    2020-01-15
    13/45/2020
    """

    assert schema(csv) == %{"d" => :string}
  end