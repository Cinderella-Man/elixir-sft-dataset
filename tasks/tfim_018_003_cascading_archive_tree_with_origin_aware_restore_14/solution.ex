    test "returns direct children sorted by id, excluding archived by default", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      sub = folder!(s, "sub", root.id)
      b = file!(s, "b.txt", root.id)
      _deep = file!(s, "deep.txt", sub.id)

      archive!(s, a.id)

      assert {:ok, children} = Archive.list_children(s, root.id)
      assert Enum.map(children, & &1.id) == [sub.id, b.id]

      assert {:ok, all} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(all, & &1.id) == Enum.sort([a.id, sub.id, b.id])
    end