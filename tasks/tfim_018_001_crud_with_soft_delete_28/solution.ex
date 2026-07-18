    test "create → read → update → soft delete → invisible → restore → visible", %{conn: conn} do
      # 1. Create
      conn_create =
        post(conn, ~p"/api/documents", %{
          "document" => %{"title" => "Lifecycle", "content" => "v1"}
        })

      id = json_response(conn_create, 201)["data"]["id"]
      assert id

      # 2. Read
      conn_show = get(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_show)["title"] == "Lifecycle"

      # 3. Update
      conn_update =
        put(conn, ~p"/api/documents/#{id}", %{
          "document" => %{"content" => "v2"}
        })

      assert json_data(conn_update)["content"] == "v2"

      # 4. Soft delete
      conn_del = delete(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_del)["deleted_at"] != nil

      # 5. Invisible by default
      conn_show2 = get(conn, ~p"/api/documents/#{id}")
      assert conn_show2.status == 404

      # 6. Still visible with flag
      conn_show3 = get(conn, ~p"/api/documents/#{id}?include_deleted=true")
      assert json_data(conn_show3)["id"] == id

      # 7. Restore
      conn_restore = post(conn, ~p"/api/documents/#{id}/restore")
      assert json_data(conn_restore)["deleted_at"] == nil

      # 8. Visible again
      conn_show4 = get(conn, ~p"/api/documents/#{id}")
      assert json_data(conn_show4)["title"] == "Lifecycle"
      assert json_data(conn_show4)["content"] == "v2"
    end