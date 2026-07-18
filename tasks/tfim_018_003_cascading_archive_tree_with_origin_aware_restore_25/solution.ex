    test "the returned target timestamp is UTC and truncated to the second", %{server: s} do
      root = folder!(s, "root")

      assert {:ok, %{node: node}} = Archive.archive_node(s, root.id)
      assert %DateTime{} = ts = node.archived_at

      # UTC zone: no offset from UTC, and the UTC zone name.
      assert ts.time_zone == "Etc/UTC"
      assert ts.utc_offset == 0
      assert ts.std_offset == 0

      # Second precision: no sub-second component survives truncation.
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts
    end