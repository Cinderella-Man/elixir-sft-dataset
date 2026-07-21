# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  test "a raising compensation does not abort the compensations that follow it" do
    Process.put(:comp_order, [])
    record = fn n -> Process.put(:comp_order, [n | Process.get(:comp_order)]) end

    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ ->
        record.(:a)
        :ua
      end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ ->
        record.(:b)
        raise "boom"
      end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> :uc end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comp, journal} = result
    # :b's compensation raises first, so :a's compensation is the one that
    # must still run after the raise.
    assert Enum.reverse(Process.get(:comp_order)) == [:b, :a]
    assert [{:b, {:exception, %RuntimeError{}, _}}, {:a, :ua}] = comp

    assert [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :fail},
             {:compensated, :b, {:exception, %RuntimeError{}, _}},
             {:compensated, :a, :ua}
           ] = journal
  end

  test "resume compensates every remaining step after a replayed step's raise" do
    Process.put(:resume_comp_order, [])
    record = fn n -> Process.put(:resume_comp_order, [n | Process.get(:resume_comp_order)]) end

    saga =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ ->
        record.(:a)
        :ua
      end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ ->
        record.(:b)
        raise "boom"
      end)
      |> Saga.step(:c, fn _ -> {:error, :late} end, fn _ -> :uc end)

    result = Saga.resume(saga, %{}, [{:completed, :a, 1}])

    assert {:error, :c, :late, comp, journal} = result
    assert Enum.reverse(Process.get(:resume_comp_order)) == [:b, :a]
    assert [{:b, {:exception, %RuntimeError{}, _}}, {:a, :ua}] = comp

    assert [
             {:completed, :a, 1},
             {:completed, :b, 2},
             {:failed, :c, :late},
             {:compensated, :b, {:exception, %RuntimeError{}, _}},
             {:compensated, :a, :ua}
           ] = journal
  end

  test "empty saga returns original context with an empty journal" do
    assert {:ok, %{x: 1}, []} = Saga.new() |> Saga.execute(%{x: 1})
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
