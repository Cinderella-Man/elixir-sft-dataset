defmodule LFUCacheTest do
  use ExUnit.Case, async: false

  defp start_cache(max_size) do
    name = :"lfu_#{System.unique_integer([:positive])}"
    start_supervised!({LFUCache, name: name, max_size: max_size})
    name
  end

  # -------------------------------------------------------
  # Basic get / put
  # -------------------------------------------------------

  test "get returns :miss for unknown key" do
    c = start_cache(3)
    assert :miss = LFUCache.get(c, :nope)
  end

  test "put and get round-trip" do
    c = start_cache(3)
    assert :ok = LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
  end

  test "put overwrites an existing key" do
    c = start_cache(3)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 42)
    assert {:ok, 42} = LFUCache.get(c, :a)
  end

  test "multiple distinct keys coexist" do
    c = start_cache(5)
    for i <- 1..5, do: LFUCache.put(c, i, i * 10)

    for i <- 1..5 do
      expected = i * 10
      assert {:ok, ^expected} = LFUCache.get(c, i)
    end
  end

  # -------------------------------------------------------
  # LFU eviction — frequency beats recency
  # -------------------------------------------------------

  test "least frequently used entry is evicted, not least recently used" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # bump :a's frequency to 2
    assert {:ok, 1} = LFUCache.get(c, :a)
    # :b is inserted more recently than :a but has frequency 1
    LFUCache.put(c, :b, 2)

    # inserting :c evicts the LFU entry — :b (freq 1), even though it is MRU
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "put-update counts as an access and raises frequency" do
    c = start_cache(2)
    LFUCache.put(c, :a, 1)
    # updating :a bumps its frequency to 2
    LFUCache.put(c, :a, 11)
    LFUCache.put(c, :b, 2)

    # :b has frequency 1, :a has frequency 2 → evict :b
    LFUCache.put(c, :c, 3)

    assert {:ok, 11} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "repeated gets protect a hot key across several evictions" do
    c = start_cache(3)
    LFUCache.put(c, :hot, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # make :hot very frequent
    for _ <- 1..5, do: LFUCache.get(c, :hot)

    # :b and :c both have freq 1; inserting :d evicts one of them (the LRU: :b)
    LFUCache.put(c, :d, 4)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 1} = LFUCache.get(c, :hot)

    # inserting :e evicts :c next; :hot still survives
    LFUCache.put(c, :e, 5)
    assert :miss = LFUCache.get(c, :c)
    assert {:ok, 1} = LFUCache.get(c, :hot)
    assert {:ok, 4} = LFUCache.get(c, :d)
    assert {:ok, 5} = LFUCache.get(c, :e)
  end

  # -------------------------------------------------------
  # Tie-break by recency among equal frequencies
  # -------------------------------------------------------

  test "ties on frequency are broken by least recently used" do
    c = start_cache(3)
    # all three inserted at freq 1, in order :a, :b, :c
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    LFUCache.put(c, :c, 3)

    # inserting :d evicts the LRU among the freq-1 entries → :a
    LFUCache.put(c, :d, 4)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
    assert {:ok, 4} = LFUCache.get(c, :d)
  end

  # -------------------------------------------------------
  # Size-1 edge case
  # -------------------------------------------------------

  test "cache of size 1 always holds only the latest inserted entry" do
    c = start_cache(1)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)

    assert :miss = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)
  end

  # -------------------------------------------------------
  # Arbitrary terms
  # -------------------------------------------------------

  test "cache stores arbitrary Elixir terms as values" do
    c = start_cache(5)
    LFUCache.put(c, :list, [1, 2, 3])
    LFUCache.put(c, :map, %{a: 1})
    LFUCache.put(c, nil, nil)

    assert {:ok, [1, 2, 3]} = LFUCache.get(c, :list)
    assert {:ok, %{a: 1}} = LFUCache.get(c, :map)
    assert {:ok, nil} = LFUCache.get(c, nil)
  end

  # -------------------------------------------------------
  # Independent instances
  # -------------------------------------------------------

  test "two cache instances are fully independent" do
    c1 = start_cache(2)
    c2 = start_cache(2)

    LFUCache.put(c1, :a, :from_c1)
    LFUCache.put(c2, :a, :from_c2)

    assert {:ok, :from_c1} = LFUCache.get(c1, :a)
    assert {:ok, :from_c2} = LFUCache.get(c2, :a)
  end

  # -------------------------------------------------------
  # :max_size validation (init raises ArgumentError)
  # -------------------------------------------------------

  test "start_link fails with ArgumentError unless :max_size is a positive integer" do
    Process.flag(:trap_exit, true)

    for bad <- [0, -1, 1.5, :many] do
      name = :"lfu_bad_#{System.pid()}_#{System.unique_integer([:positive])}"

      assert {:error, {%ArgumentError{}, _stack}} =
               LFUCache.start_link(name: name, max_size: bad)
    end
  end

  # -------------------------------------------------------
  # Frequency arithmetic: each access is worth exactly +1
  # -------------------------------------------------------

  test "a get bumps frequency by exactly one, so a twice-read key outranks a once-read key" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two gets)
    LFUCache.put(c, :a, 1)
    assert {:ok, 1} = LFUCache.get(c, :a)
    assert {:ok, 1} = LFUCache.get(c, :a)

    # :b reaches frequency 2 (insert + one get) and is the most recently used
    LFUCache.put(c, :b, 2)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 3)

    assert {:ok, 1} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  test "a put-update bumps frequency by exactly one, so extra writes outrank fewer writes" do
    c = start_cache(2)

    # :a reaches frequency 3 (insert + two updates)
    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :a, 2)
    LFUCache.put(c, :a, 3)

    # :b reaches frequency 2 (insert + one update) and is the most recently used
    LFUCache.put(c, :b, 1)
    LFUCache.put(c, :b, 2)

    # cache is full: the lowest frequency loses — :b (freq 2) not :a (freq 3)
    LFUCache.put(c, :c, 9)

    assert {:ok, 3} = LFUCache.get(c, :a)
    assert :miss = LFUCache.get(c, :b)
    assert {:ok, 9} = LFUCache.get(c, :c)
  end

  # -------------------------------------------------------
  # Entry count: updates never evict, new keys evict exactly one
  # -------------------------------------------------------

  test "entry count stays at max_size: updates evict nothing, a new key evicts exactly one" do
    c = start_cache(2)
    data = :"#{c}_data"

    LFUCache.put(c, :a, 1)
    LFUCache.put(c, :b, 2)
    assert :ets.info(data, :size) == 2

    # updating an existing key while exactly at max_size must not evict anything
    LFUCache.put(c, :a, 11)
    assert :ets.info(data, :size) == 2
    assert {:ok, 11} = LFUCache.get(c, :a)
    assert {:ok, 2} = LFUCache.get(c, :b)

    # a new key while at max_size evicts exactly one entry before inserting
    LFUCache.put(c, :c, 3)
    assert :ets.info(data, :size) == 2
    assert {:ok, 3} = LFUCache.get(c, :c)
  end

  # -------------------------------------------------------
  # On-disk row shape: callers may read data rows directly
  # -------------------------------------------------------

  test "a data row is {key, {value, frequency, seq}} with the triple nested, not flattened" do
    c = start_cache(3)
    data = :"#{c}_data"

    # a brand-new entry is stored at frequency 1 alongside its recency stamp
    LFUCache.put(c, :a, :v1)
    assert [{:a, {:v1, 1, seq1}}] = :ets.lookup(data, :a)
    assert is_integer(seq1)

    # a hit raises the frequency in place and draws a strictly larger stamp
    assert {:ok, :v1} = LFUCache.get(c, :a)
    assert [{:a, {:v1, 2, seq2}}] = :ets.lookup(data, :a)
    assert is_integer(seq2)
    assert seq2 > seq1

    # an update rewrites the value inside the same nested triple
    LFUCache.put(c, :a, :v2)
    assert [{:a, {:v2, 3, seq3}}] = :ets.lookup(data, :a)
    assert is_integer(seq3)
    assert seq3 > seq2
  end

  test "each live entry holds a unique recency stamp that grows with insertion order" do
    c = start_cache(4)
    data = :"#{c}_data"

    for k <- [:a, :b, :c, :d], do: LFUCache.put(c, k, k)

    stamps =
      for k <- [:a, :b, :c, :d] do
        assert [{^k, {^k, 1, seq}}] = :ets.lookup(data, k)
        assert is_integer(seq)
        seq
      end

    # no two live entries share a stamp, and every insert drew a larger one
    assert length(Enum.uniq(stamps)) == 4
    assert stamps == Enum.sort(stamps)
  end

  test "an evicted key leaves no row behind and restarts at frequency 1 when re-put" do
    c = start_cache(2)
    data = :"#{c}_data"

    # :a reaches frequency 4, :b reaches frequency 3
    LFUCache.put(c, :a, 1)
    for _ <- 1..3, do: LFUCache.get(c, :a)
    LFUCache.put(c, :b, 2)
    for _ <- 1..2, do: LFUCache.get(c, :b)

    # :b is the least frequently used, so inserting :c removes its row entirely
    LFUCache.put(c, :c, 3)
    assert :ets.lookup(data, :b) == []

    # re-inserting :b does not remember the frequency it had before eviction
    LFUCache.put(c, :b, 20)
    assert [{:b, {20, 1, _seq}}] = :ets.lookup(data, :b)
  end

  test "start_link fails with ArgumentError when :max_size is missing entirely" do
    Process.flag(:trap_exit, true)
    name = :"lfu_missing_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:error, {%ArgumentError{}, _stack}} = LFUCache.start_link(name: name)
  end

  test "a miss creates nothing and disturbs no eviction state" do
    name = :"lfu_miss_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, _} = LFUCache.start_link(name: name, max_size: 2)
    data = :"#{name}_data"

    LFUCache.put(name, :a, 1)
    LFUCache.put(name, :b, 2)

    # Hammer a missing key: still :miss every time, and the documented
    # entry-count channel shows no entry was ever created for it.
    for _ <- 1..10, do: assert(:miss = LFUCache.get(name, :nope))
    assert :ets.info(data, :size) == 2

    # Frequencies were not disturbed either: one real access makes :a the
    # survivor, and inserting :c evicts :b exactly as if no miss happened.
    assert {:ok, 1} = LFUCache.get(name, :a)
    LFUCache.put(name, :c, 3)
    assert :miss = LFUCache.get(name, :b)
    assert {:ok, 1} = LFUCache.get(name, :a)
  end
end
