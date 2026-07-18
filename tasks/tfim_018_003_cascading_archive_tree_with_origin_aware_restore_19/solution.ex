    test "rejects invalid names", %{server: s} do
      root = folder!(s, "root")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "  ")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, 7)
    end