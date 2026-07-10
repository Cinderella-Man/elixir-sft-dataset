  test "clean/0 without a prior start/2 returns :ok" do
    assert DBCleaner.clean() == :ok
  end