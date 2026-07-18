  test "locked key-paths supplied as tuples are honoured" do
    s = start(base: %{db: %{password: "s3cr3t", host: "localhost"}}, locked: [{:db, :password}])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "evil.host"}})

    assert ConfigStore.get(s, [:db, :password]) == "s3cr3t"
    assert ConfigStore.get(s, [:db, :host]) == "evil.host"
  end