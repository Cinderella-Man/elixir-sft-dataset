    test "concurrent updates with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..30
        |> Enum.map(fn i ->
          Task.async(fn -> Documents.update_document(srv, doc.id, %{title: "t#{i}"}, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :stale_version, 1}, &1)) == 29
    end