  test "a zero timeout on an exhausted pool returns an error without blocking" do
    start_supervised!({ValidatingPool, name: :vp_zero, max_size: 1})
    assert {:ok, _c} = ValidatingPool.checkout(:vp_zero, 100)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_zero, 0)

    s = ValidatingPool.stats(:vp_zero)
    assert s.total == 1 and s.in_use == 1 and s.available == 0
  end