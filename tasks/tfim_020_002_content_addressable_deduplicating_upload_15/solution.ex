  test "store get returns error for unknown id", _ctx do
    start_supervised!({FileUpload.Store, name: :lonely})
    assert {:error, :not_found} = FileUpload.Store.get(:lonely, "deadbeef")
  end