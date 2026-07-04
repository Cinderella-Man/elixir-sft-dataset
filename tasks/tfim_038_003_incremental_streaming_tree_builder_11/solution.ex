  test "detects a direct cycle in the current node set" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: 2})
    TreeStream.add(pid, %{id: 2, parent_id: 1})

    assert {:error, {:cycle_detected, ids}} = TreeStream.forest(pid)
    assert Enum.sort(ids) == [1, 2]
    TreeStream.stop(pid)
  end