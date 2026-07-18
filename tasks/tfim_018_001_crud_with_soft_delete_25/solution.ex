    test "restored document appears in default listings again", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      post(conn, ~p"/api/documents/#{doc.id}/restore")

      conn = get(conn, ~p"/api/documents")
      ids = Enum.map(json_response(conn, 200)["data"], & &1["id"])
      assert doc.id in ids
    end