  test "keeps duplicate events for a key rather than deduplicating them" do
    agg = start_agg(batch_size: 4, interval_ms: 30_000)

    Enum.each([:dup, :dup, :other, :dup], fn ev -> KeyedAggregator.push(agg, :k, ev) end)

    assert_receive {:flushed, :k, [:dup, :dup, :other, :dup]}, 1_000
  end