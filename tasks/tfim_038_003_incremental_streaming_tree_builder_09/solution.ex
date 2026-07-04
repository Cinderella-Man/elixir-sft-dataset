  test "orphans are discarded by default" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 2, parent_id: 99})

    assert {:ok, roots} = TreeStream.forest(pid)
    assert collect_ids(roots) == [1]
    TreeStream.stop(pid)
  end