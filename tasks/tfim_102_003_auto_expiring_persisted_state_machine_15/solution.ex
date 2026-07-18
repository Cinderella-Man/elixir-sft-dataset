  test "transition/3 reports a db error and leaves the in-memory state untouched" do
    {:module, failing_repo, _, _} =
      defmodule FailingRepo do
        def one(_query), do: nil
        def all(_query), do: []
        def insert(_struct), do: {:error, :disk_full}
      end

    {:ok, sm} = StateMachine.start_link(repo: failing_repo)
    {:ok, :pending} = StateMachine.start(sm, "order:dbfail")

    assert {:error, {:db_error, :disk_full}} =
             StateMachine.transition(sm, "order:dbfail", :confirm)

    assert {:ok, :pending} = StateMachine.get_state(sm, "order:dbfail")
  end