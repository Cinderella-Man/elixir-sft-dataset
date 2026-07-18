  test "add/2 preserves every previously set bit as items accumulate" do
    start = BloomFilter.new(200, 0.01)

    Enum.reduce(1..50, start, fn i, f ->
      next = BloomFilter.add(f, {:grow, i})

      assert tuple_size(next.bits) == tuple_size(f.bits)

      for wi <- 0..(tuple_size(f.bits) - 1) do
        old_word = elem(f.bits, wi)
        assert Bitwise.band(old_word, elem(next.bits, wi)) == old_word
      end

      assert BloomFilter.member?(next, {:grow, i})
      next
    end)
  end