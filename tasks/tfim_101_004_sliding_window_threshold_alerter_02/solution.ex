  test "unknown key has count zero and status :ok", %{sc: sc} do
    assert 0 = SlidingAlerter.count(sc, "new_key")
    assert :ok = SlidingAlerter.status(sc, "new_key")
  end