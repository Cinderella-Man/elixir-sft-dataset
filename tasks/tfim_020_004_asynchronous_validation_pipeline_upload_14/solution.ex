  test "update_status on unknown id returns error", _ctx do
    start_supervised!({FileUpload.Store, name: :other_store})
    assert {:error, :not_found} = FileUpload.Store.update_status(:other_store, "x", :valid, %{})
  end