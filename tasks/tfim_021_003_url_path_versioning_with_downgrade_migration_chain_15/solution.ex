  test "400 body carries the exact unsupported-version error payload" do
    conn = call("/api/v4/users/1")

    assert conn.status == 400

    assert json_body(conn) == %{
             "error" => "unsupported version",
             "supported" => ["v1", "v2", "v3"]
           }
  end