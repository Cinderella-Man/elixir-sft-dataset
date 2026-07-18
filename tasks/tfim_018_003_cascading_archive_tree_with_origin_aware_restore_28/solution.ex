    test "restores a directly archived node and its cascade", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      assert {:ok, %{node: node, restored: restored}} = Archive.unarchive_node(s, root.id)
      assert node.archived_at == nil
      assert node.archive_origin == nil
      assert restored == Enum.sort([sub.id, a.id])

      for id <- [root.id, sub.id, a.id] do
        assert {:ok, n} = Archive.fetch_node(s, id)
        assert n.archived_at == nil
        assert n.archive_origin == nil
      end

      assert {:ok, []} = Archive.list_archived(s)
    end