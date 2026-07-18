  test "locked key at one path does not protect same key at another path" do
    base = %{
      primary: %{token: "real_token"},
      secondary: %{token: "also_real"}
    }

    override = %{
      primary: %{token: "fake_token"},
      secondary: %{token: "replaced"}
    }

    result =
      ConfigMerger.merge(base, override, locked: [[:primary, :token]])

    assert result.primary.token == "real_token"
    assert result.secondary.token == "replaced"
  end