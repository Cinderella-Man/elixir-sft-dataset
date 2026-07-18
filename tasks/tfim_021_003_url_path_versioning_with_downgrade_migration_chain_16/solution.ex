  test "404 body for a missing user is exactly the not-found payload" do
    for version <- ["v1", "v2", "v3"] do
      conn = call("/api/#{version}/users/nope")

      assert conn.status == 404
      assert json_body(conn) == %{"error" => "not found"}
    end
  end