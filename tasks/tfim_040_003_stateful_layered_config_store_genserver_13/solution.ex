  test "locked key-path absent from the base cannot be introduced by a layer" do
    s = start(base: %{db: %{host: "localhost"}}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned"}})

    assert ConfigStore.get(s, [:db, :password]) == nil
    assert ConfigStore.get(s, [:db, :host]) == "localhost"
  end