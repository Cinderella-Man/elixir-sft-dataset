  test "a quoted empty field is a non-null string value" do
    csv = ~s(a,b\n"",1\nx,2\n)

    result = schema(csv)
    assert result["a"] == %{type: :string, nullable: false, unique: true}
    assert result["b"] == %{type: :integer, nullable: false, unique: true}
  end