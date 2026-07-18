    test "returns :not_found for files and unknown ids", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:error, :not_found} = Archive.list_children(s, f.id)
      assert {:error, :not_found} = Archive.list_children(s, 999)
    end