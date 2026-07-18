  test "the order table holds exactly one freshly stamped row per resident key" do
    c = start_cache(2)

    LRUCache.put(c, :a, 1)
    LRUCache.put(c, :b, 2)

    # Overwrite and read :a; its stale ordering rows must be gone.
    LRUCache.put(c, :a, 11)
    assert {:ok, 11} = LRUCache.get(c, :a)

    # ts 1 (:a inserted), 2 (:b inserted), 3 (:a overwritten), 4 (:a read).
    assert :ets.tab2list(order_table(c)) == [{2, :b}, {4, :a}]

    # Evicting the LRU (:b) removes its row and stamps the newcomer next.
    LRUCache.put(c, :c, 3)
    assert :ets.tab2list(order_table(c)) == [{4, :a}, {5, :c}]
  end