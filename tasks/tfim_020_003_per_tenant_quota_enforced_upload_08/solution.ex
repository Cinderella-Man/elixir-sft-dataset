  test "delete frees quota and allows re-upload", _ctx do
    start_supervised!({FileUpload.Store, name: :qd, quota_bytes: 8})
    o = opts_for(:qd)

    up = upload_conn(o, "A", "a.csv", "a,b\n1,2\n")
    assert up.status == 201
    id = json_body(up)["id"]

    # full now
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 507

    del = delete_conn(o, "A", id)
    assert del.status == 200
    dbody = json_body(del)
    assert dbody["freed_bytes"] == 8
    assert dbody["used_bytes"] == 0
    assert FileUpload.Store.usage(:qd, "A") == 0
    refute File.exists?(Path.join(@upload_dir, id <> ".csv"))

    # budget freed, re-upload works
    assert upload_conn(o, "A", "c.csv", "e,f\n5,6\n").status == 201
  end