  test "single root has depth 0 and single-element path" do
    assert {:ok, [node]} = TreePaths.build([%{id: 1, parent_id: nil, name: "root"}])
    assert node.id == 1
    assert node.name == "root"
    assert node.depth == 0
    assert node.path == [1]
  end