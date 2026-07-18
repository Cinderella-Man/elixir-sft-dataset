  test "named server can be addressed by its registered name" do
    {:ok, _pid} = ConfigStore.start_link(name: :cfg_named_test, base: %{a: 1})
    ConfigStore.put_layer(:cfg_named_test, :env, %{a: 2})

    assert ConfigStore.get(:cfg_named_test, [:a]) == 2
  end