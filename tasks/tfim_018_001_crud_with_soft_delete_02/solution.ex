    test "creates a document with valid attrs", %{conn: conn} do
      conn =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "My Doc", "content" => "Hello"}
        })

      data = json_response(conn, 201)["data"]
      assert data["id"]
      assert data["title"] == "My Doc"
      assert data["content"] == "Hello"
      assert data["deleted_at"] == nil
      assert data["inserted_at"]
      assert data["updated_at"]
    end