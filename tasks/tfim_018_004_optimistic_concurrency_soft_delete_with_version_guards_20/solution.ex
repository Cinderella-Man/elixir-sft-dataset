    test "concurrent soft-deletes with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn -> Documents.soft_delete_document(srv, doc.id, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      oks = Enum.count(results, &match?({:ok, _}, &1))
      stale = Enum.count(results, &match?({:error, :stale_version, 1}, &1))

      assert oks == 1
      assert stale == 49

      {:ok, d} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert d.lock_version == 1
      assert d.deleted_at != nil
    end