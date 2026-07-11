  test "a column with mixed unrelated types defaults to string" do
    csv = """
    val
    1
    hello
    """

    assert schema(csv) == %{"val" => :string}
  end