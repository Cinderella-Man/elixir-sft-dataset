  test "missing file field returns 422", %{opts: opts} do
    conn =
      conn(:post, "/api/uploads", %{"nope" => "x"})
      |> put_req_header("content-type", "multipart/form-data")
      |> FileUpload.Router.call(opts)

    assert conn.status == 422
    assert json_body(conn)["error"] =~ "No file"
  end