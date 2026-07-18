    test "empty folder yields an empty list", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, []} = Archive.list_children(s, root.id)
    end