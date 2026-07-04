  test "multiple roots preserve input order" do
    items = [
      %{id: :c, parent_id: nil},
      %{id: :a, parent_id: nil},
      %{id: :b, parent_id: nil}
    ]

    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == [:c, :a, :b]
    assert Enum.all?(nodes, &(&1.depth == 0))
  end