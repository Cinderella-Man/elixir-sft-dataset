  test "builds a nested tree from incrementally added nodes" do
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil})
    assert :ok = TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert :ok = TreeStream.add(pid, %{id: 3, parent_id: 1})

    assert TreeStream.count(pid) == 3
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == 1
    assert Enum.map(root.children, & &1.id) == [2, 3]
    TreeStream.stop(pid)
  end