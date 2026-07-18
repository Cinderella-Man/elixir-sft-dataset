  test "explicit :discard strategy drops orphans and their descendants from the forest" do
    {:ok, pid} = TreeStream.start_link(orphan_strategy: :discard)
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 2, parent_id: 99})
    TreeStream.add(pid, %{id: 3, parent_id: 2})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == 1
    assert root.children == []
    assert TreeStream.count(pid) == 3
    TreeStream.stop(pid)
  end