  test "nested locked violation is detected" do
    base = %{db: %{password: "s3cr3t"}}
    override = %{db: %{password: "pwned"}}

    assert {:error, [conflict]} =
             StrictConfigMerger.merge(base, override, locked: [[:db, :password]])

    assert conflict.type == :locked_violation
    assert conflict.path == [:db, :password]
  end