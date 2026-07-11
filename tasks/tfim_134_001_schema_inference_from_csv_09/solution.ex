  test "an all-null (empty) column is typed as string" do
    csv = """
    a,b
    1,
    2,
    """

    assert schema(csv) == %{"a" => :integer, "b" => :string}
  end