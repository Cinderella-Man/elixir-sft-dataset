    test "a directly archived file also carries a UTC second-precision stamp", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert %DateTime{} = ts = node.archived_at
      assert ts.time_zone == "Etc/UTC"
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts

      assert {:ok, listed} = Archive.list_archived(s)
      assert [only] = listed
      assert only.id == f.id
      assert only.archived_at == ts
    end