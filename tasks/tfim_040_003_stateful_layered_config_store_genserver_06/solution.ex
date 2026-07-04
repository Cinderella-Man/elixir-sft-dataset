  test "replacing a layer keeps its precedence position" do
    s = start(base: %{v: 0})
    ConfigStore.put_layer(s, :low, %{v: 1})
    ConfigStore.put_layer(s, :high, %{v: 2})

    # Re-put :low with a new value; it must still be lower precedence than :high.
    ConfigStore.put_layer(s, :low, %{v: 99})

    assert ConfigStore.layers(s) == [:low, :high]
    assert ConfigStore.get_config(s).v == 2
  end