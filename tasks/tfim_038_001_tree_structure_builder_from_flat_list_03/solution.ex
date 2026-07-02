  test "single root node with no children" do
    item = %{id: 1, parent_id: nil, name: "root"}
    assert {:ok, [node]} = TreeBuilder.build([item])
    assert node.id == 1
    assert node.name == "root"
    assert node.children == []
  end