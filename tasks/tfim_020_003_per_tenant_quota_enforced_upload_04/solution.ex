  test "quota is enforced per-account and independent", _ctx do
    start_supervised!({FileUpload.Store, name: :q16, quota_bytes: 16})
    o = opts_for(:q16)

    # acct A fills its own budget
    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 201
    # A is now full
    assert upload_conn(o, "A", "c.csv", "e,f\n5,6\n").status == 507
    # B has its own fresh budget
    assert upload_conn(o, "B", "a.csv", "a,b\n1,2\n").status == 201
  end