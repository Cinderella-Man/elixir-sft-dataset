  test "a column of all integers is integer" do
    csv = """
    n
    1
    2
    3
    """

    assert schema(csv) == %{"n" => :integer}
  end