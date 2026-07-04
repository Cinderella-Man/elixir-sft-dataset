  test "add_many adds all and skips duplicates" do
    {:ok, pid} = TreeStream.start_link()

    assert :ok =
             TreeStream.add_many(pid, [
               %{id: 1, parent_id: nil},
               %{id: 2, parent_id: 1},
               %{id: 1, parent_id: nil},
               %{id: 3, parent_id: 1}
             ])

    assert TreeStream.count(pid) == 3
    assert {:ok, [root]} = TreeStream.forest(pid)
    assert Enum.map(root.children, & &1.id) == [2, 3]
    TreeStream.stop(pid)
  end