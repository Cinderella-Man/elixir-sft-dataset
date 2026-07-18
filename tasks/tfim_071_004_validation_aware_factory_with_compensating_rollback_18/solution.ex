  test "sequence/2 returns distinct values" do
    a = Factory.sequence(:s3, fn n -> n end)
    b = Factory.sequence(:s3, fn n -> n end)
    assert a != b
  end