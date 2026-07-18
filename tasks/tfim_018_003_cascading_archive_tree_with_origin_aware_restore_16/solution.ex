    test "archived folder is hidden unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      child = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.list_children(s, root.id)

      assert {:ok, children} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(children, & &1.id) == [child.id]
    end