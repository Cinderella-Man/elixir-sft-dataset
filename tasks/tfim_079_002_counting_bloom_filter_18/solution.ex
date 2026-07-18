  test "remove/2 never decrements a saturated counter" do
    empty = CountingBloomFilter.new(50, 0.01)

    saturated =
      Enum.reduce(1..400, empty, fn _i, f -> CountingBloomFilter.add(f, "hot") end)

    frozen = saturated.counters
    assert Enum.max(Tuple.to_list(frozen)) == 255

    # A single removal must leave the saturated slots at 255, not 254.
    once = CountingBloomFilter.remove(saturated, "hot")
    assert once.counters == frozen

    # Draining far past the number of inserts must still not touch them, so the
    # item stays a member: a saturated counter can never produce a false negative.
    drained =
      Enum.reduce(1..400, saturated, fn _i, f -> CountingBloomFilter.remove(f, "hot") end)

    assert drained.counters == frozen
    assert CountingBloomFilter.member?(drained, "hot")
  end