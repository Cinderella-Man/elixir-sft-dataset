    test "returns 422 for invalid update (empty title)", %{conn: conn} do
      doc = create_document()

      conn =
        put(conn, ~p"/api/documents/#{doc.id}", %{
          "document" => %{"title" => ""}
        })

      errors = json_errors(conn, 422)
      assert errors["title"]
    end