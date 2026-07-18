    test "a cascade-archived node cannot be restored on its own", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :cascade_archived} = Archive.unarchive_node(s, a.id)
      assert {:error, :not_found} = Archive.fetch_node(s, a.id)
    end