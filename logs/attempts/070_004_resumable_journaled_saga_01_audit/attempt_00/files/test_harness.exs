defmodule SagaTest do
  use ExUnit.Case, async: false

  test "execute returns final context and a chronological journal on success" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn ctx -> {:ok, ctx.a + 1} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:ok, ctx, journal} = result
    assert ctx.a == 1 and ctx.b == 2
    assert journal == [{:completed, :a, 1}, {:completed, :b, 2}]
  end

  test "execute failure journal records completed, failed and compensated events" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:error, :boom} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, comp, journal} = result
    assert comp == [a: :ua]

    assert journal == [
             {:completed, :a, 1},
             {:failed, :b, :boom},
             {:compensated, :a, :ua}
           ]
  end

  test "resume continues from a journal without re-running completed actions" do
    Process.put(:ran, [])
    mark = fn n -> Process.put(:ran, [n | Process.get(:ran)]) end

    saga =
      Saga.new()
      |> Saga.step(
        :a,
        fn _ ->
          mark.(:a)
          {:ok, 1}
        end,
        fn _ -> :ua end
      )
      |> Saga.step(
        :b,
        fn _ ->
          mark.(:b)
          {:ok, 2}
        end,
        fn _ -> :ub end
      )
      |> Saga.step(
        :c,
        fn ctx ->
          mark.(:c)
          {:ok, ctx.a + ctx.b}
        end,
        fn _ -> :uc end
      )

    journal = [{:completed, :a, 1}, {:completed, :b, 2}]
    result = Saga.resume(saga, %{}, journal)

    assert {:ok, ctx, jr} = result
    assert ctx.a == 1 and ctx.b == 2 and ctx.c == 3
    # Only :c actually executed during the resume.
    assert Enum.reverse(Process.get(:ran)) == [:c]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:completed, :c, 3}
           ]
  end

  test "resume compensates journaled and newly run steps in reverse on failure" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :late} end, fn _ -> :uc end)

    journal = [{:completed, :a, 1}]
    result = Saga.resume(saga, %{}, journal)

    assert {:error, :c, :late, comp, jr} = result
    assert comp == [b: :ub, a: :ua]

    assert jr == [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :late},
             {:compensated, :b, :ub},
             {:compensated, :a, :ua}
           ]
  end

  test "resume with an empty journal behaves like execute" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)

    assert Saga.resume(saga, %{}, []) == Saga.execute(saga, %{})
  end

  test "resume merges journaled results into the context for later steps" do
    saga =
      Saga.new()
      |> Saga.step(:base, fn _ -> {:ok, 10} end, fn _ -> nil end)
      |> Saga.step(:derived, fn ctx -> {:ok, ctx.base * 3} end, fn _ -> nil end)

    result = Saga.resume(saga, %{}, [{:completed, :base, 10}])
    assert {:ok, ctx, _jr} = result
    assert ctx.derived == 30
  end

  test "all compensations run even if one raises" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise "boom" end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp, _journal} = result
    assert comp[:b] == :ub
    assert match?({:exception, _, _}, comp[:a])
  end

  test "empty saga returns original context with an empty journal" do
    assert {:ok, %{x: 1}, []} = Saga.new() |> Saga.execute(%{x: 1})
  end

  test "raising compensation records the exception struct and stacktrace in results and journal" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> raise ArgumentError, "bad thing" end)
      |> Saga.step(:b, fn _ -> {:error, :stop} end, fn _ -> :ub end)
      |> Saga.execute(%{})

    assert {:error, :b, :stop, comp, journal} = result
    assert {:exception, %ArgumentError{message: "bad thing"}, stack} = comp[:a]
    assert is_list(stack)
    assert Enum.all?(stack, &is_tuple/1)
    assert Enum.member?(journal, {:compensated, :a, comp[:a]})
    assert Enum.member?(journal, {:compensated, :b, :ub})
  end

  test "resume drops failed and compensated events from the incoming journal" do
    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ua end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :ub end)

    journal = [
      {:completed, :a, 1},
      {:failed, :b, :boom},
      {:compensated, :a, :ua}
    ]

    assert {:ok, ctx, jr} = Saga.resume(saga, %{}, journal)
    assert ctx == %{a: 1, b: 2}
    assert jr == [{:completed, :a, 1}, {:completed, :b, 2}]
  end

  test "resume with every step already journaled runs no actions and returns the journal" do
    parent = self()

    saga =
      Saga.new()
      |> Saga.step(
        :a,
        fn _ ->
          send(parent, :ran_a)
          {:ok, 1}
        end,
        fn _ -> :ua end
      )
      |> Saga.step(
        :b,
        fn _ ->
          send(parent, :ran_b)
          {:ok, 2}
        end,
        fn _ -> :ub end
      )

    journal = [{:completed, :a, 9}, {:completed, :b, 8}]

    assert {:ok, ctx, jr} = Saga.resume(saga, %{}, journal)
    assert ctx == %{a: 9, b: 8}
    assert jr == journal
    refute_receive :ran_a, 50
    refute_receive :ran_b, 50
  end

  test "compensating functions receive the accumulated context at failure time" do
    parent = self()

    result =
      Saga.new()
      |> Saga.step(
        :a,
        fn _ -> {:ok, 1} end,
        fn ctx ->
          send(parent, {:comp_ctx, :a, ctx})
          :ua
        end
      )
      |> Saga.step(
        :b,
        fn _ -> {:ok, 2} end,
        fn ctx ->
          send(parent, {:comp_ctx, :b, ctx})
          :ub
        end
      )
      |> Saga.step(:c, fn _ -> {:error, :nope} end, fn _ -> :uc end)
      |> Saga.execute(%{seed: 0})

    assert {:error, :c, :nope, _comp, _journal} = result
    assert_receive {:comp_ctx, :b, ctx_b}, 100
    assert ctx_b == %{seed: 0, a: 1, b: 2}
    assert_receive {:comp_ctx, :a, ctx_a}, 100
    assert ctx_a == %{seed: 0, a: 1, b: 2}
  end

  test "failure on the first step yields no compensations and a journal with only the failure" do
    parent = self()

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:error, :early} end, fn _ -> :ua end)
      |> Saga.step(
        :b,
        fn _ ->
          send(parent, :ran_b)
          {:ok, 2}
        end,
        fn _ -> :ub end
      )
      |> Saga.execute(%{})

    assert {:error, :a, :early, [], [{:failed, :a, :early}]} = result
    refute_receive :ran_b, 50
  end
end
