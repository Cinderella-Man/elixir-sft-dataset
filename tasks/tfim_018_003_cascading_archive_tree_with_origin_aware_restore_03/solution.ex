    test "creates a nested folder", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, child} = Archive.create_folder(s, %{name: "child", parent_id: root.id})
      assert child.parent_id == root.id
    end