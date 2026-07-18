    test "cannot rename archived or unknown nodes", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.rename_node(s, root.id, "nope")
      assert {:error, :not_found} = Archive.rename_node(s, 999, "nope")
    end