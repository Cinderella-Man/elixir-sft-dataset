  test "uploaded_at is a valid ISO 8601 string and stable across dedup", %{opts: opts} do
    content = "a,b\n1,2\n"
    b1 = json_body(call_upload(opts, "t1.csv", content))
    b2 = json_body(call_upload(opts, "t2.csv", content))
    assert {:ok, _dt, _} = DateTime.from_iso8601(b1["uploaded_at"])
    assert b1["uploaded_at"] == b2["uploaded_at"]
  end