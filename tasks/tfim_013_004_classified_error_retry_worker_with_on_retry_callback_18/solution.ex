  test "accepts a name option and is reachable by that registered name" do
    name = :classified_retry_named_worker

    {:ok, _pid} =
      ClassifiedRetryWorker.start_link(
        name: name,
        clock: &Clock.now/0,
        random: &ZeroRandom.rand/1
      )

    func = fn -> {:ok, :via_name} end

    assert {:ok, :via_name} = ClassifiedRetryWorker.execute(name, func, [])
  end