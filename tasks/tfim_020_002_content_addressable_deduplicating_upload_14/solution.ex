  test "metadata is retrievable from the store, and list dedups", %{opts: opts} do
    content = "p,q\n1,2\n"
    call_upload(opts, "s1.csv", content)
    call_upload(opts, "s2.csv", content)

    files = FileUpload.Store.list(:test_store)
    assert length(files) == 1
    [rec] = files
    assert {:ok, got} = FileUpload.Store.get(:test_store, rec.id)
    assert got.upload_count == 2
  end