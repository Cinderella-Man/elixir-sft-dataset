  test "store list and get reflect saved records", %{opts: opts} do
    up = upload_conn(opts, "acct1", "s.csv", "x,y\n1,2\n")
    id = json_body(up)["id"]
    assert {:ok, rec} = FileUpload.Store.get(:big_store, id)
    assert rec.account == "acct1"
    assert length(FileUpload.Store.list(:big_store)) == 1
  end