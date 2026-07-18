    test "errors for unknown and already-archived nodes", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :already_archived} = Archive.archive_node(s, root.id)
      assert {:error, :not_found} = Archive.archive_node(s, 999)
    end