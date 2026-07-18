  test "append list strategy + locked key in same merge" do
    base = %{
      allowed: ["user_a"],
      pin: "1234"
    }

    override = %{
      allowed: ["user_b"],
      pin: "9999"
    }

    result =
      ConfigMerger.merge(base, override,
        list_strategy: :append,
        locked: [[:pin]]
      )

    assert result.allowed == ["user_a", "user_b"]
    assert result.pin == "1234"
  end