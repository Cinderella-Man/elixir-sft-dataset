  test "missing file field returns 422", %{opts: opts} do
    base =
      conn(:post, "/api/uploads", %{"nope" => "x"})
      |> put_req_header("content-type", "multipart/form-data")
      |> put_req_header("x-account-id", "acct1")

    conn = FileUpload.Router.call(base, opts)
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "No file"
  end