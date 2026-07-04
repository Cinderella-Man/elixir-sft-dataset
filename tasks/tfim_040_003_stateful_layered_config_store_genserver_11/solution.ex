  test "locked key-path cannot be changed by any layer" do
    s = start(base: %{db: %{password: "s3cr3t", host: "localhost"}}, locked: [[:db, :password]])
    ConfigStore.put_layer(s, :env, %{db: %{password: "pwned", host: "evil.host"}})

    cfg = ConfigStore.get_config(s)
    assert cfg.db.password == "s3cr3t"
    assert cfg.db.host == "evil.host"
  end