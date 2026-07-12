    test "stale version is rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v1"}, 0)

      assert {:error, :stale_version, 1} =
               Documents.update_document(srv, doc.id, %{title: "v2"}, 0)
    end