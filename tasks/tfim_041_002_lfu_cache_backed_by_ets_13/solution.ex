  test "start_link fails with ArgumentError unless :max_size is a positive integer" do
    Process.flag(:trap_exit, true)

    for bad <- [0, -1, 1.5, :many] do
      name = :"lfu_bad_#{System.pid()}_#{System.unique_integer([:positive])}"

      assert {:error, {%ArgumentError{}, _stack}} =
               LFUCache.start_link(name: name, max_size: bad)
    end
  end