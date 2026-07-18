    test "renames a live folder and file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, renamed} = Archive.rename_node(s, root.id, "archive")
      assert renamed.name == "archive"
      assert {:ok, again} = Archive.fetch_node(s, root.id)
      assert again.name == "archive"

      assert {:ok, rf} = Archive.rename_node(s, f.id, "b.txt")
      assert rf.name == "b.txt"
      assert rf.content == "body"
    end