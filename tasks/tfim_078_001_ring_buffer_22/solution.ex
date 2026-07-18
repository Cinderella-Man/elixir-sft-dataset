  test "backing store is a pre-allocated tuple with one slot per capacity unit" do
    cap = 5
    empty = RingBuffer.new(cap)

    fixed_tuples = fn buf ->
      buf
      |> Map.from_struct()
      |> Map.values()
      |> Enum.filter(fn value -> is_tuple(value) and tuple_size(value) == cap end)
    end

    # Pre-allocated at construction time, before anything was ever pushed.
    assert fixed_tuples.(empty) != []

    full = Enum.reduce(1..(cap * 3), empty, fn i, b -> RingBuffer.push(b, i) end)

    # Still exactly `capacity` slots after many wrapping overwrites.
    assert fixed_tuples.(full) != []
    assert RingBuffer.size(full) == cap
    assert RingBuffer.to_list(full) == [11, 12, 13, 14, 15]
  end