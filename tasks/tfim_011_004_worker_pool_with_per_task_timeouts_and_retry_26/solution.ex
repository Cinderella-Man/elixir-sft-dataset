  test "await delivers to the submitting process only, as documented", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, quick_task(:mine))

    # Another process awaiting the same ref gets nothing: results are
    # messages in the SUBMITTER's mailbox.
    other =
      Task.async(fn ->
        RetryPool.await(pool, ref, 150)
      end)

    assert {:error, :timeout} = Task.await(other, 1_000)

    # The submitter still receives the result afterwards.
    assert {:ok, :mine} = RetryPool.await(pool, ref, 1_000)
  end