  test "subscribers/2 lists subs sorted by descending priority", %{bus: bus} do
    s1 = spawn_sub(:s1)
    s2 = spawn_sub(:s2)
    s3 = spawn_sub(:s3)

    r1 = sub!(bus, "t", s1, 5)
    r2 = sub!(bus, "t", s2, 10)
    r3 = sub!(bus, "t", s3, 5)

    subs = PriorityEventBus.subscribers(bus, "t")

    # s2 (priority 10) first; then s1 and s3 (priority 5), oldest subscription first
    assert [{^r2, ^s2, 10}, {^r1, ^s1, 5}, {^r3, ^s3, 5}] = subs
  end