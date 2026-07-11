  test "log returns error for unknown commit hash", %{store: s} do
    assert {:error, :not_found} = ObjectStore.log(s, "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
  end