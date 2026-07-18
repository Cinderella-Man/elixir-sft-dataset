  test "the default create function hands out distinct references" do
    start_supervised!({ValidatingPool, name: :vp_defcreate, max_size: 2})
    assert {:ok, r1} = ValidatingPool.checkout(:vp_defcreate, 100)
    assert {:ok, r2} = ValidatingPool.checkout(:vp_defcreate, 100)
    assert is_reference(r1)
    assert is_reference(r2)
    assert r1 != r2
  end