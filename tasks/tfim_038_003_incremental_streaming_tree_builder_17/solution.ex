  test "atom ids nest correctly and duplicate detection compares them by value" do
    {:ok, pid} = TreeStream.start_link()
    assert :ok = TreeStream.add(pid, %{id: :root, parent_id: nil})
    assert :ok = TreeStream.add(pid, %{id: :leaf, parent_id: :root})

    assert {:error, {:duplicate_id, :leaf}} =
             TreeStream.add(pid, %{id: :leaf, parent_id: nil})

    assert TreeStream.count(pid) == 2
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert root.id == :root
    assert [%{id: :leaf, children: []}] = root.children
    TreeStream.stop(pid)
  end