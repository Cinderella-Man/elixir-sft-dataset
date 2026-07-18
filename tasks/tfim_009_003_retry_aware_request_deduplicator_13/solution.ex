  test "status returns :idle for unknown key", %{rd: rd} do
    assert RetryDedup.status(rd, "nothing") == :idle
  end