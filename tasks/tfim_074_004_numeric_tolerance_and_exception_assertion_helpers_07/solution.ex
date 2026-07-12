    test "passes when actual is within the allowed percentage" do
      assert_within_pct(101, 100, 5)
    end