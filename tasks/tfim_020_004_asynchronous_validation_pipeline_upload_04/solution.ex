  test "valid JSON eventually transitions to valid", %{opts: opts} do
    conn = post_upload(opts, "d.json", Jason.encode!(%{"k" => "v"}))
    id = json_body(conn)["id"]
    rec = await_settled(:test_store, id)
    assert rec.status == :valid
    assert json_body(get_status(opts, id))["status"] == "valid"
  end