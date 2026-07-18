  test "session ids are unpadded url-safe base64 of 16 random bytes", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # 16 bytes base64-encoded without padding is exactly 22 characters.
    assert String.length(id) == 22
    refute String.contains?(id, "=")
    assert id =~ ~r/\A[A-Za-z0-9_-]+\z/
  end