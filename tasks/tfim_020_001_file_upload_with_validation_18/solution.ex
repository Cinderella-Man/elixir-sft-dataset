  test "returns 422 when no file field is provided", %{opts: opts} do
    {req_body, content_type} = multipart_field_body("not_file", "something")
    conn = post_multipart(opts, req_body, content_type)

    assert conn.status == 422
    body = json_body(conn)
    assert body["error"] =~ "No file"
  end