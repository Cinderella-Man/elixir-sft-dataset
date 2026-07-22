  test "start_link fails with ArgumentError when :max_size is missing entirely" do
    Process.flag(:trap_exit, true)
    name = :"lfu_missing_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{}, _stack}} = LFUCache.start_link(name: name)
  end