  test "store list returns all uploaded files", %{opts: opts} do
    call_upload(opts, "a.csv", "h1,h2\n1,2\n")
    call_upload(opts, "b.json", Jason.encode!(%{"k" => "v"}))

    files = FileUpload.Store.list(:test_store)
    assert length(files) == 2

    names = Enum.map(files, & &1.original_name) |> Enum.sort()
    assert names == ["a.csv", "b.json"]
  end