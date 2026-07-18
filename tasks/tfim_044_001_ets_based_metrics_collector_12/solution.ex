  test "increment accepts an amount of 0 and leaves an existing counter unchanged" do
    Metrics.increment(:zero_bump, 7)
    assert :ok = Metrics.increment(:zero_bump, 0)
    assert Metrics.get(:zero_bump) == 7
    assert :ok = Metrics.increment(:zero_bump, 0)
    assert Metrics.get(:zero_bump) == 7
  end