  test "a mix of date and datetime cells defaults to string" do
    csv = """
    x
    2020-01-15
    2020-01-15T10:00:00
    """

    assert schema(csv) == %{"x" => :string}
  end