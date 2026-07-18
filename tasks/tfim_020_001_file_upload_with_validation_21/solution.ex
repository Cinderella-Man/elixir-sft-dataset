  test "store get returns error for unknown id", _ctx do
    # An explicit child id so a second store can run under the test supervisor
    # regardless of how the solution's `child_spec/1` derives its id — the
    # prompt only requires `start_link` to accept a `:name` option.
    lonely = Supervisor.child_spec({FileUpload.Store, name: :lonely_store}, id: :lonely_store)
    start_supervised!(lonely)
    assert {:error, :not_found} = FileUpload.Store.get(:lonely_store, "nonexistent-uuid")
  end