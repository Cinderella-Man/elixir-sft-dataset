  test "hands out distinct connections up to max_size" do
    start_supervised!({ValidatingPool, name: :vp_distinct, max_size: 2})
    assert {:ok, c1} = ValidatingPool.checkout(:vp_distinct, 100)
    assert {:ok, c2} = ValidatingPool.checkout(:vp_distinct, 100)
    assert c1 != c2
  end