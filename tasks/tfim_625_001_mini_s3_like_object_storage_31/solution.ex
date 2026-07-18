  test "basic multipart upload and reassembly", %{os: os} do
    ObjectStorage.create_bucket(os, "b")

    assert {:ok, upload_id} =
             ObjectStorage.start_multipart(os, "b", "big-file.bin", "application/octet-stream", %{
               "source" => "upload"
             })

    assert is_binary(upload_id)

    assert :ok = ObjectStorage.upload_part(os, upload_id, 1, "AAA")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 2, "BBB")
    assert :ok = ObjectStorage.upload_part(os, upload_id, 3, "CCC")

    assert :ok = ObjectStorage.complete_multipart(os, upload_id)

    assert {:ok, obj} = ObjectStorage.get_object(os, "b", "big-file.bin")
    assert obj.data == "AAABBBCCC"
    assert obj.content_type == "application/octet-stream"
    assert obj.metadata == %{"source" => "upload"}
    assert obj.size == 9
  end