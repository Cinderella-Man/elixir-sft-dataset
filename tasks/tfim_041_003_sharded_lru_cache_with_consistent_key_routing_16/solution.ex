  test "child_spec carries the documented id, type, restart and shutdown" do
    opts = [name: :child_spec_probe, num_shards: 2, max_size: 3]
    spec = LRUCacheSharded.child_spec(opts)

    assert %{id: :child_spec_probe, type: :worker, restart: :permanent, shutdown: 5_000} = spec
    assert {LRUCacheSharded, :start_link, [passed]} = spec.start
    assert passed[:num_shards] == 2
    assert passed[:max_size] == 3
  end