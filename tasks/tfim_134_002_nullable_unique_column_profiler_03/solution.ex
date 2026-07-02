  test "nullable is true when an unquoted empty field appears" do
    csv = """
    a,b
    1,x
    ,x
    """

    result = schema(csv)
    assert result["a"] == %{type: :integer, nullable: true, unique: true}
    assert result["b"] == %{type: :string, nullable: false, unique: false}
  end