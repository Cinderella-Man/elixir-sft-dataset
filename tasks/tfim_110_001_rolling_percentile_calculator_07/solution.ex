  test "querying an unknown series returns :empty" do
    start_server([])
    assert {:error, :empty} = Percentile.query(:nope, 0.5)
  end