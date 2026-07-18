  test "a quoted empty field is a non-null string cell that widens the column" do
    csv = """
    a
    1
    ""
    """

    assert schema(csv) == %{"a" => :string}
  end