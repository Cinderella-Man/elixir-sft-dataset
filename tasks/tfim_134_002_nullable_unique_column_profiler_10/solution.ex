  test "missing fields (ragged rows) count as null" do
    csv = """
    1,2
    3
    """

    result = schema(csv, headers: false)
    assert result["column_1"] == %{type: :integer, nullable: false, unique: true}
    assert result["column_2"] == %{type: :integer, nullable: true, unique: true}
  end