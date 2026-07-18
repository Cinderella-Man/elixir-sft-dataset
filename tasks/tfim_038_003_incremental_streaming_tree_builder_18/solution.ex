  test "add_many returns :ok for an empty list and for an all-duplicate list" do
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add_many(pid, [])
    assert TreeStream.count(pid) == 0
    assert {:ok, []} = TreeStream.forest(pid)

    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil, v: :first})
    assert :ok = TreeStream.add_many(pid, [%{id: 1, parent_id: nil, v: :second}])

    assert TreeStream.count(pid) == 1
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.v == :first
    TreeStream.stop(pid)
  end