  test "store list contains created records", %{opts: opts} do
    post_upload(opts, "a.csv", "x,y\n1,2\n")
    post_upload(opts, "b.json", Jason.encode!(%{"ok" => true}))
    assert length(FileUpload.Store.list(:test_store)) == 2
  end