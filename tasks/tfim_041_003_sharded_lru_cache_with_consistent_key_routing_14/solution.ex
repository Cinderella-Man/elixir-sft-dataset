  test "invalid :max_size fails the start with an ArgumentError naming the option" do
    Process.flag(:trap_exit, true)
    n1 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m1}, _stack}} =
             LRUCacheSharded.start_link(name: n1, num_shards: 2, max_size: -3)

    assert m1 =~ ":max_size"
    assert m1 =~ "-3"

    n2 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m2}, _stack}} =
             LRUCacheSharded.start_link(name: n2, num_shards: 2, max_size: :lots)

    assert m2 =~ ":max_size"
    assert m2 =~ ":lots"
  end