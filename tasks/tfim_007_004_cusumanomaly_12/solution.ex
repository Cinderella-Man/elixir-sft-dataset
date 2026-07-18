  test "invalid options raise at start_link" do
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(threshold: 0) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(threshold: -1) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(slack: -0.1) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(warmup_samples: 0) end
    assert_raise ArgumentError, fn -> CusumAnomaly.start_link(epsilon: 0) end
  end