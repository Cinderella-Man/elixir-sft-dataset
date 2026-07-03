  test "deduplication does not create a second file on disk", %{opts: opts} do
    content = "a,b\n1,2\n"
    call_upload(opts, "one.csv", content)
    call_upload(opts, "two.csv", content)

    files = File.ls!(@upload_dir)
    assert length(files) == 1
  end