  test "duplicate add is rejected and leaves state unchanged" do
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add(pid, %{id: 1, parent_id: nil, v: :first})
    assert {:error, {:duplicate_id, 1}} =
             TreeStream.add(pid, %{id: 1, parent_id: nil, v: :second})

    assert TreeStream.count(pid) == 1
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.v == :first
    TreeStream.stop(pid)
  end