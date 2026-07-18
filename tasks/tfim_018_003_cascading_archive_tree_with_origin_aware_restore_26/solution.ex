    test "stored timestamps on target and cascade are UTC second-precision", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      leaf = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      for id <- [root.id, sub.id, leaf.id] do
        assert {:ok, stored} = Archive.fetch_node(s, id, include_archived: true)
        assert %DateTime{} = ts = stored.archived_at
        assert ts.time_zone == "Etc/UTC"
        assert ts.utc_offset == 0
        assert ts.std_offset == 0
        assert ts.microsecond == {0, 0}
        assert DateTime.truncate(ts, :second) == ts
      end
    end