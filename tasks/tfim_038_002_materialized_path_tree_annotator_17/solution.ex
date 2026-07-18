  test "subtree returns error for an unknown id" do
    assert {:ok, nodes} = TreePaths.build([%{id: 1, parent_id: nil}])
    assert {:error, :not_found} = TreePaths.subtree(nodes, 999)
  end