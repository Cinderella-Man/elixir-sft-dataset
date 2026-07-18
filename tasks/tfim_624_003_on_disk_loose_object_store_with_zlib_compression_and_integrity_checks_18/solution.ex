  test "start_link without the required :dir option raises" do
    assert_raise KeyError, fn -> ObjectStore.start_link([]) end
    assert_raise KeyError, fn -> ObjectStore.start_link(name: :objstore_no_dir) end
  end