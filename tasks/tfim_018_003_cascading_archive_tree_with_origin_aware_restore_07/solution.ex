    test "creates a file inside a folder with default content", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, f} = Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
      assert f.type == :file
      assert f.content == ""
      assert f.parent_id == root.id
      assert f.archived_at == nil

      assert {:ok, g} =
               Archive.create_file(s, %{name: "b.txt", parent_id: root.id, content: "hello"})

      assert g.content == "hello"
    end