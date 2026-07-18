    test "returns 404 for soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => "Can't touch this"}
        })

      assert json_errors(conn, 404)["detail"] == "Not found"
    end