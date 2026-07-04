  test "different content produces different ids and two files", %{opts: opts} do
    c1 = call_upload(opts, "a.csv", "a,b\n1,2\n")
    c2 = call_upload(opts, "b.csv", "c,d\n3,4\n")

    assert c1.status == 201
    assert c2.status == 201
    assert json_body(c1)["id"] != json_body(c2)["id"]
    assert length(File.ls!(@upload_dir)) == 2
  end