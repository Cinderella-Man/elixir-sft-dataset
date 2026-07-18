    test "already-archived descendants are left untouched and not reported", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      %{node: sub_archived} = archive!(s, sub.id)
      assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)

      assert cascaded == [loose.id]

      assert {:ok, sub_now} = Archive.fetch_node(s, sub.id, include_archived: true)
      assert sub_now.archive_origin == :direct
      assert sub_now.archived_at == sub_archived.archived_at

      assert {:ok, deep_now} = Archive.fetch_node(s, deep.id, include_archived: true)
      assert deep_now.archive_origin == :cascade
    end