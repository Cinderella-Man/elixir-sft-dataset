  test "a crashed holder's connection is reclaimed" do
    start_supervised!({ValidatingPool, name: :vp_crash, min_size: 0, max_size: 1})
    {holder, {:ok, _conn}} = spawn_holder(:vp_crash, 1_000)
    assert {:error, :timeout} = ValidatingPool.checkout(:vp_crash, 50)
    Process.exit(holder, :kill)
    assert {:ok, _reclaimed} = ValidatingPool.checkout(:vp_crash, 1_000)
  end