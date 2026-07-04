  test "over-quota upload returns 507 and consumes nothing", _ctx do
    start_supervised!({FileUpload.Store, name: :q10, quota_bytes: 10})
    o = opts_for(:q10)

    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    before = FileUpload.Store.usage(:q10, "A")

    conn = upload_conn(o, "A", "big.csv", "aa,bb\n11,22\n")
    assert conn.status == 507
    body = json_body(conn)
    assert body["error"] =~ "Quota exceeded"
    assert body["quota_bytes"] == 10
    assert body["used_bytes"] == before
    assert body["requested_bytes"] == byte_size("aa,bb\n11,22\n")
    # usage unchanged, no extra disk file
    assert FileUpload.Store.usage(:q10, "A") == before
    assert length(File.ls!(@upload_dir)) == 1
  end