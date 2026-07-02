  test "returns empty forest for empty input" do
    assert {:ok, []} = TreeBuilder.build([])
  end