  test "two tokens issued with the same payload and ttl are different binaries",
       %{server: server} do
    # Each call mints a fresh random nonce, so identical arguments still yield
    # distinct tokens even though the clock is frozen.
    t1 = SingleUseToken.issue(server, %{user_id: 7}, 300)
    t2 = SingleUseToken.issue(server, %{user_id: 7}, 300)

    refute t1 == t2
  end