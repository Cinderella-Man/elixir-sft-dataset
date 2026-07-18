  test "metadata is retrievable from the store after upload", %{opts: opts} do
    csv_content = "x,y\n1,2\n"
    conn = call_upload(opts, "stored.csv", csv_content)
    assert conn.status == 201

    body = json_body(conn)
    id = body["id"]

    assert {:ok, meta} = FileUpload.Store.get(:test_store, id)
    assert meta.original_name == "stored.csv"
    assert meta.size == byte_size(csv_content)
  end