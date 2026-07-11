  test "an all-null column is string, nullable, and trivially unique" do
    csv = """
    a,b
    1,
    2,
    """

    result = schema(csv)
    assert result["a"] == %{type: :integer, nullable: false, unique: true}
    assert result["b"] == %{type: :string, nullable: true, unique: true}
  end