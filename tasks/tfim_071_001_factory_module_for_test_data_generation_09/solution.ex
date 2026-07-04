  test "sequence/2 returns distinct values on consecutive calls" do
    e1 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)
    e2 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)
    e3 = Factory.sequence(:email_seq_test, fn n -> "user#{n}@test.com" end)

    assert e1 != e2
    assert e2 != e3
    assert e1 != e3
  end