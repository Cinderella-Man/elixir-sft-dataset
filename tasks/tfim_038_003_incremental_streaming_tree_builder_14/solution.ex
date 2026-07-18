  test "forest adds the :children key and no other key to each node map" do
    {:ok, pid} = TreeStream.start_link()
    TreeStream.add(pid, %{id: 1, parent_id: nil, label: "root", score: 9})
    TreeStream.add(pid, %{id: 2, parent_id: 1, note: :leafy})

    assert {:ok, [root]} = TreeStream.forest(pid)
    assert Enum.sort(Map.keys(root)) == Enum.sort([:id, :parent_id, :label, :score, :children])
    assert [child] = root.children
    assert Enum.sort(Map.keys(child)) == Enum.sort([:id, :parent_id, :note, :children])
    TreeStream.stop(pid)
  end