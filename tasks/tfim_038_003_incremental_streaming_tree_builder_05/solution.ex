  test "root and sibling order follow insertion order, not id order" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 10, parent_id: nil})
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 5, parent_id: 10})
    TreeStream.add(pid, %{id: 2, parent_id: 10})

    assert {:ok, [first, second]} = TreeStream.forest(pid)
    assert first.id == 10
    assert second.id == 1
    assert Enum.map(first.children, & &1.id) == [5, 2]
    TreeStream.stop(pid)
  end