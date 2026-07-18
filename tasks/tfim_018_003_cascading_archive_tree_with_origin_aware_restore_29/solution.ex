    test "a directly archived child stays archived when the parent is restored", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
      assert restored == [loose.id]

      assert {:ok, _} = Archive.fetch_node(s, loose.id)
      assert {:error, :not_found} = Archive.fetch_node(s, sub.id)
      assert {:error, :not_found} = Archive.fetch_node(s, deep.id)

      assert {:ok, archived} = Archive.list_archived(s)
      assert Enum.map(archived, & &1.id) == Enum.sort([sub.id, deep.id])
    end