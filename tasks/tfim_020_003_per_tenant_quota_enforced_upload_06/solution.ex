  test "exactly at quota succeeds, one byte over fails", _ctx do
    start_supervised!({FileUpload.Store, name: :q8, quota_bytes: 8})
    o = opts_for(:q8)

    # exactly 8 bytes
    assert upload_conn(o, "A", "a.csv", "a,b\n1,2\n").status == 201
    assert FileUpload.Store.usage(:q8, "A") == 8
    # any further byte exceeds
    assert upload_conn(o, "A", "b.csv", "c,d\n3,4\n").status == 507
  end