  test "orphans are discarded by default" do
    items = [
      %{id: 1, parent_id: nil},
      %{id: 2, parent_id: 99}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [1]
  end