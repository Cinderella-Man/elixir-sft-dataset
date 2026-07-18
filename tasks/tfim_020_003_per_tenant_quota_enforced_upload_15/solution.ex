  test "uploaded_at is valid ISO 8601", %{opts: opts} do
    up = upload_conn(opts, "acct1", "t.csv", "a,b\n1,2\n")
    assert {:ok, _dt, _} = DateTime.from_iso8601(json_body(up)["uploaded_at"])
  end