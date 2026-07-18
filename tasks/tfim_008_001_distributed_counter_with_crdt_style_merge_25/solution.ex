  test "many nodes with small counts", %{c: c} do
    for i <- 1..100 do
      Counter.increment(c, :"node_#{i}", 1)
    end

    assert Counter.value(c) == 100
  end