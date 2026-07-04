  test ":raise_to_root promotes orphans to roots" do
    {:ok, pid} = TreeStream.start_link(orphan_strategy: :raise_to_root)
    TreeStream.add(pid, %{id: 1, parent_id: nil})
    TreeStream.add(pid, %{id: 2, parent_id: 99})
    TreeStream.add(pid, %{id: 3, parent_id: 2})

    assert {:ok, roots} = TreeStream.forest(pid)
    all = collect_ids(roots)
    assert Enum.sort(all) == [1, 2, 3]
    orphan_root = Enum.find(roots, &(&1.id == 2))
    assert [%{id: 3}] = orphan_root.children
    TreeStream.stop(pid)
  end