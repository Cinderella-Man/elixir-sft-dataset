    test "returns 404 when deleting an already soft-deleted document", %{conn: conn} do
      doc = create_document()
      soft_delete!(doc)

      conn = delete(conn, ~p"/api/documents/#{doc.id}")
      assert json_errors(conn, 404)["detail"] == "Not found"
    end