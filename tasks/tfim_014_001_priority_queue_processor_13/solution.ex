  test "repeated drain/enqueue cycles keep processing each new task", %{pq: pq} do
    for n <- 1..5 do
      PriorityQueue.enqueue(pq, n, :normal)
      assert :ok = PriorityQueue.drain(pq)

      processed_so_far = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
      assert processed_so_far == Enum.to_list(1..n)
    end
  end