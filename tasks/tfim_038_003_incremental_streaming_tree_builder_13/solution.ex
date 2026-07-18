  test "forest reflects state as it grows across multiple queries" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    assert {:ok, [%{children: []}]} = TreeStream.forest(pid)

    TreeStream.add(pid, %{id: 2, parent_id: 1})
    assert {:ok, [%{children: [%{id: 2}]}]} = TreeStream.forest(pid)
    TreeStream.stop(pid)
  end