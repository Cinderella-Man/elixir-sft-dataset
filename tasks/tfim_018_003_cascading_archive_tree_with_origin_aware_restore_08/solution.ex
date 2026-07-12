    test "requires a folder parent", %{server: s} do
      assert {:error, :parent_not_found} = Archive.create_file(s, %{name: "a.txt"})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: nil})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: 42})
    end