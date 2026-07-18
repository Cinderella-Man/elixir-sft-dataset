  test "locked key inside deep map with other keys merging normally" do
    base = %{
      app: %{
        auth: %{secret_key: "do-not-touch", algo: "HS256"},
        name: "MyApp"
      }
    }

    override = %{
      app: %{
        auth: %{secret_key: "compromised", algo: "RS256"},
        name: "EvilApp"
      }
    }

    result =
      ConfigMerger.merge(base, override, locked: [[:app, :auth, :secret_key]])

    assert result.app.auth.secret_key == "do-not-touch"
    assert result.app.auth.algo == "RS256"
    assert result.app.name == "EvilApp"
  end