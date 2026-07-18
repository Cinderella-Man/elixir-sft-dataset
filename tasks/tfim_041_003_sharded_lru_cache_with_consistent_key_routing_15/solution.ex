  test "a missing required option fails loudly instead of defaulting" do
    Process.flag(:trap_exit, true)
    name = :"shard_#{System.unique_integer([:positive])}"

    assert {:error, {%KeyError{key: :max_size}, _stack}} =
             LRUCacheSharded.start_link(name: name, num_shards: 2)

    assert {:error, {%KeyError{key: :num_shards}, _stack}} =
             LRUCacheSharded.start_link(name: :"#{name}_b", max_size: 4)

    assert_raise KeyError, fn ->
      LRUCacheSharded.start_link(num_shards: 2, max_size: 4)
    end
  end