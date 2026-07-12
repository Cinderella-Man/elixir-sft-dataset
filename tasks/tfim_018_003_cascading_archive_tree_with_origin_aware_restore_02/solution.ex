    test "creates a root folder with sequential ids", %{server: s} do
      assert {:ok, a} = Archive.create_folder(s, %{name: "root"})
      assert a.id == 1
      assert a.type == :folder
      assert a.name == "root"
      assert a.parent_id == nil
      assert a.content == nil
      assert a.archived_at == nil
      assert a.archive_origin == nil

      assert {:ok, b} = Archive.create_folder(s, %{name: "other"})
      assert b.id == 2
    end