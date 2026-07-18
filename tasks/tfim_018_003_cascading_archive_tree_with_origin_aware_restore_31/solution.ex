    test "cannot restore while the parent is still archived", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:error, :parent_archived} = Archive.unarchive_node(s, sub.id)

      assert {:ok, _} = Archive.unarchive_node(s, root.id)
      assert {:ok, %{node: node}} = Archive.unarchive_node(s, sub.id)
      assert node.archived_at == nil
    end