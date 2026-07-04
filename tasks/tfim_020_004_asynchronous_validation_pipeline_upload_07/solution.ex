  test "malformed JSON transitions to invalid", %{opts: opts} do
    conn = post_upload(opts, "bad.json", "{nope")
    id = json_body(conn)["id"]
    rec = await_settled(:test_store, id)
    assert rec.status == :invalid
    assert json_body(get_status(opts, id))["error"] =~ "Invalid JSON"
  end