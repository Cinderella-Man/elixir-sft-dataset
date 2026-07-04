  test "disallowed type transitions to invalid via the async pipeline", %{opts: opts} do
    conn = post_upload(opts, "notes.txt", "hello")
    assert conn.status == 202
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :invalid
    assert json_body(get_status(opts, id))["error"] =~ "not allowed"
  end