  test "repeated touches keep a session alive indefinitely", %{store: store} do
    {:ok, id} = SessionStore.create(store, %{user: "alice"})

    # Touch every 800ms for 5 cycles — total elapsed 4000ms >> timeout of 1000ms
    for _ <- 1..5 do
      Clock.advance(800)
      assert :ok = SessionStore.touch(store, id)
    end

    assert {:ok, %{user: "alice"}} = SessionStore.get(store, id)
  end