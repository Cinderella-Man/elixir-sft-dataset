  test "a quoted empty field counts as a non-null string cell" do
    csv = """
    a
    1
    ""
    2
    """

    assert schema(csv) == %{"a" => :string}
  end