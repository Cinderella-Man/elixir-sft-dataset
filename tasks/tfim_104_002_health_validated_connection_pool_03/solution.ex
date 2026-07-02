  test "exhaustion times out cleanly, checkin frees a slot" do
    start_supervised!({ValidatingPool, name: :vp_basic, max_size: 1})
    assert {:ok, c} = ValidatingPool.checkout(:vp_basic, 100)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_basic, 20)
    assert :ok = ValidatingPool.checkin(:vp_basic, c)
    assert {:ok, ^c} = ValidatingPool.checkout(:vp_basic, 100)
  end