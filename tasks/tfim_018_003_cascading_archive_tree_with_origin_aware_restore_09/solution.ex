    test "rejects an archived parent folder", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
    end