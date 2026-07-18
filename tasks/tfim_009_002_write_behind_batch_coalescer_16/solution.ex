  test "named process registration works" do
    {:ok, _pid} = BatchCollector.start_link(flush_interval_ms: 100, name: :my_batcher)

    assert {:ok, [:hello]} =
             BatchCollector.submit(:my_batcher, :k, :hello, fn items -> {:ok, items} end)
  end