    test "archiving a file affects only that file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert node.id == f.id
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at

      assert {:ok, _} = Archive.fetch_node(s, root.id)
      assert {:error, :not_found} = Archive.fetch_node(s, f.id)
    end