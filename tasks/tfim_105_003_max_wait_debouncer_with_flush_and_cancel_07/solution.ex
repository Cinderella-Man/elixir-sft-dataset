  test "flush with nothing pending is a no-op returning :ok" do
    assert :ok = MaxWaitDebouncer.flush("absent")
    refute_receive _, 100
  end