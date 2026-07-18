  test "detects an indirect cycle" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: 3})
    TreeStream.add(pid, %{id: 2, parent_id: 1})
    TreeStream.add(pid, %{id: 3, parent_id: 2})

    assert {:error, {:cycle_detected, ids}} = TreeStream.forest(pid)
    assert Enum.sort(ids) == [1, 2, 3]
    TreeStream.stop(pid)
  end