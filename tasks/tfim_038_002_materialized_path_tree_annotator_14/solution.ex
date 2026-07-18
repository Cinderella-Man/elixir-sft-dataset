  test "no false positive on a valid deep tree" do
    items = for i <- 1..20, do: %{id: i, parent_id: if(i == 1, do: nil, else: i - 1)}
    assert {:ok, nodes} = TreePaths.build(items)
    assert ids(nodes) == Enum.to_list(1..20)
    assert List.last(nodes).depth == 19
  end