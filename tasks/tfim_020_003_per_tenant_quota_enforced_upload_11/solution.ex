  test "validation still enforced (invalid CSV -> 422, no quota used)", _ctx do
    start_supervised!({FileUpload.Store, name: :qv, quota_bytes: 1000})
    o = opts_for(:qv)
    conn = upload_conn(o, "A", "bad.csv", "singlevalue")
    assert conn.status == 422
    assert json_body(conn)["error"] =~ "Invalid CSV"
    assert FileUpload.Store.usage(:qv, "A") == 0
  end