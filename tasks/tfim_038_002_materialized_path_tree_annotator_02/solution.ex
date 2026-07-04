  test "returns empty list for empty input" do
    assert {:ok, []} = TreePaths.build([])
  end