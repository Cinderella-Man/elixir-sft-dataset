  test "handles a child added before its parent (out-of-order)" do
    {:ok, pid} = TreeStream.start_link()
    # grandchild first, then child, then root
    assert :ok = TreeStream.add(pid, %{id: 3, parent_id: 2})
    assert :ok = TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == 1
    assert [%{id: 2, children: [%{id: 3}]}] = root.children
    TreeStream.stop(pid)
  end