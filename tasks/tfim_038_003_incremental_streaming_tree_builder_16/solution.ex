  test "nesting is identical for two servers fed the same nodes in different orders" do
    {:ok, forward} = TreeStream.start_link()
    TreeStream.add(forward, %{id: 1, parent_id: nil, tag: :a})
    TreeStream.add(forward, %{id: 2, parent_id: 1, tag: :b})
    TreeStream.add(forward, %{id: 3, parent_id: 2, tag: :c})
    TreeStream.add(forward, %{id: 4, parent_id: 1, tag: :d})

    {:ok, backward} = TreeStream.start_link()
    TreeStream.add(backward, %{id: 2, parent_id: 1, tag: :b})
    TreeStream.add(backward, %{id: 3, parent_id: 2, tag: :c})
    TreeStream.add(backward, %{id: 4, parent_id: 1, tag: :d})
    TreeStream.add(backward, %{id: 1, parent_id: nil, tag: :a})

    assert {:ok, forest_a} = TreeStream.forest(forward)
    assert {:ok, forest_b} = TreeStream.forest(backward)
    assert forest_a == forest_b
    TreeStream.stop(forward)
    TreeStream.stop(backward)
  end