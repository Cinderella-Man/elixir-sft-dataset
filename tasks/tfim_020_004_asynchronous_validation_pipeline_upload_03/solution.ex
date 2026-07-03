  test "valid CSV eventually transitions to valid with a download_url", %{opts: opts} do
    conn = post_upload(opts, "ok.csv", "a,b\n1,2\n")
    id = json_body(conn)["id"]

    rec = await_settled(:test_store, id)
    assert rec.status == :valid

    got = get_status(opts, id)
    assert got.status == 200
    body = json_body(got)
    assert body["status"] == "valid"
    assert String.contains?(body["download_url"], id)
  end