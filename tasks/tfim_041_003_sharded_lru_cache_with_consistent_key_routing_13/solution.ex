  test "invalid :num_shards fails the start with an ArgumentError naming the option" do
    Process.flag(:trap_exit, true)
    n1 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m1}, _stack}} =
             LRUCacheSharded.start_link(name: n1, num_shards: 0, max_size: 4)

    assert m1 =~ ":num_shards"
    assert m1 =~ "0"

    n2 = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{message: m2}, _stack}} =
             LRUCacheSharded.start_link(name: n2, num_shards: 2.0, max_size: 4)

    assert m2 =~ ":num_shards"
    assert m2 =~ "2.0"
  end