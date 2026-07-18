  test "concurrent add and remove: add wins" do
    {:ok, node_a} = ORSet.start_link([])
    {:ok, node_b} = ORSet.start_link([])

    # Both start with :x
    ORSet.add(node_a, :x, :a)
    state_a = ORSet.state(node_a)
    ORSet.merge(node_b, state_a)

    # Now both have :x with tag {:a, 1}
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true

    # CONCURRENT: node_a re-adds :x (new tag {:a, 2}), node_b removes :x
    ORSet.add(node_a, :x, :a)
    ORSet.remove(node_b, :x)

    # node_a: :x has tags [{:a, 1}, {:a, 2}]
    # node_b: :x removed (tombstones: [{:a, 1}])
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == false

    # Bidirectional merge
    sa = ORSet.state(node_a)
    sb = ORSet.state(node_b)
    ORSet.merge(node_a, sb)
    ORSet.merge(node_b, sa)

    # ADD WINS: :x is present because {:a, 2} is NOT in node_b's tombstones
    assert ORSet.member?(node_a, :x) == true
    assert ORSet.member?(node_b, :x) == true
  end