    test "archiving a folder cascades to the whole subtree with one timestamp", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", root.id)
      b = file!(s, "b.txt", sub.id)

      assert {:ok, %{node: node, cascaded: cascaded}} = Archive.archive_node(s, root.id)
      assert node.archive_origin == :direct
      assert cascaded == Enum.sort([sub.id, a.id, b.id])

      for id <- cascaded do
        assert {:ok, n} = Archive.fetch_node(s, id, include_archived: true)
        assert n.archive_origin == :cascade
        assert n.archived_at == node.archived_at
        assert {:error, :not_found} = Archive.fetch_node(s, id)
      end
    end