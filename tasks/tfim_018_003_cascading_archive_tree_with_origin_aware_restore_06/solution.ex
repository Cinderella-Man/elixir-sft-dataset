    test "rejects an archived parent", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_folder(s, %{name: "x", parent_id: root.id})
    end