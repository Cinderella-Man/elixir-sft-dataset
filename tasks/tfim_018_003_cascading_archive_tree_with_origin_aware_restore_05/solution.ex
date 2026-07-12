    test "rejects a missing or non-folder parent", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "note.txt", root.id)

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: 999})

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: f.id})
    end