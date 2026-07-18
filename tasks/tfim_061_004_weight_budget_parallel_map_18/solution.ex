  test "WeightMeter can be reached through a registered :name" do
    {:ok, pid} = WeightMeter.start_link(name: :audit_weight_meter)

    assert Process.whereis(:audit_weight_meter) == pid
    assert WeightMeter.add(:audit_weight_meter, 4) == 4
    assert WeightMeter.add(:audit_weight_meter, 3) == 7
    assert WeightMeter.sub(:audit_weight_meter, 7) == 0
    assert WeightMeter.peak(:audit_weight_meter) == 7
  end