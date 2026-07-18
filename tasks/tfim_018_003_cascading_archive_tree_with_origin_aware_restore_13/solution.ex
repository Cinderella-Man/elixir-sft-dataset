    test "hides archived nodes unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.fetch_node(s, root.id)
      assert {:ok, node} = Archive.fetch_node(s, root.id, include_archived: true)
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at
    end