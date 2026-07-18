defmodule SagaTest do
  use ExUnit.Case, async: false

  defp track(key, value) do
    Process.put(key, [value | Process.get(key, [])])
  end

  defp tracked(key), do: Process.get(key, []) |> Enum.reverse()

  test "executes all compensable steps and threads enriched context" do
    result =
      Saga.new()
      |> Saga.step(:reserve, fn ctx -> {:ok, "res:#{ctx.user}"} end, fn _ -> :cancel end)
      |> Saga.step(:charge, fn ctx -> {:ok, "chg:#{ctx.reserve}"} end, fn _ -> :refund end)
      |> Saga.execute(%{user: "alice"})

    assert {:ok, ctx} = result
    assert ctx.reserve == "res:alice"
    assert ctx.charge == "chg:res:alice"
  end

  test "retriable step retries until it succeeds and merges its result" do
    Process.put(:attempts, 0)

    result =
      Saga.new()
      |> Saga.step(:reserve, fn _ -> {:ok, :r} end, fn _ -> :undo end)
      |> Saga.retriable(
        :commit,
        fn _ ->
          n = Process.get(:attempts) + 1
          Process.put(:attempts, n)
          if n < 3, do: {:error, :flaky}, else: {:ok, :committed}
        end,
        5
      )
      |> Saga.execute(%{})

    assert {:ok, ctx} = result
    assert ctx.commit == :committed
    assert Process.get(:attempts) == 3
  end

  test "retriable step exhaustion returns error and compensates nothing" do
    Process.put(:comp, [])

    result =
      Saga.new()
      |> Saga.step(:reserve, fn _ -> {:ok, :r} end, fn _ -> track(:comp, :reserve) end)
      |> Saga.retriable(:commit, fn _ -> {:error, :down} end, 3)
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, :down}, []} = result
    assert tracked(:comp) == []
  end

  test "retriable action is invoked exactly max_attempts times on exhaustion" do
    Process.put(:calls, 0)

    Saga.new()
    |> Saga.retriable(
      :p,
      fn _ ->
        Process.put(:calls, Process.get(:calls) + 1)
        {:error, :nope}
      end,
      4
    )
    |> Saga.execute(%{})

    assert Process.get(:calls) == 4
  end

  test "compensable failure rolls back prior compensable steps in reverse" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ca end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ -> :cb end)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :cc end)
      |> Saga.execute(%{})

    assert {:error, :c, :boom, [b: :cb, a: :ca]} = result
  end

  test "compensable failure after a retriable step never compensates the retriable step" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ -> :ca end)
      |> Saga.retriable(:p, fn _ -> {:ok, :pivot} end, 2)
      |> Saga.step(:b, fn _ -> {:error, :boom} end, fn _ -> :cb end)
      |> Saga.execute(%{})

    assert {:error, :b, :boom, [a: :ca]} = result
  end

  test "retriable action sees context enriched by prior steps" do
    Saga.new()
    |> Saga.step(:seed, fn _ -> {:ok, 41} end, fn _ -> nil end)
    |> Saga.retriable(
      :p,
      fn ctx ->
        track(:seen, ctx.seed)
        {:ok, ctx.seed + 1}
      end,
      2
    )
    |> Saga.execute(%{})

    assert tracked(:seen) == [41]
  end

  test "all compensations run even if one raises" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, :ok} end, fn _ ->
        track(:ran, :a)
        raise "boom in compensation a"
      end)
      |> Saga.step(:b, fn _ -> {:ok, :ok} end, fn _ -> track(:ran, :b) end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> track(:ran, :c) end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, _} = result
    assert :a in tracked(:ran)
    assert :b in tracked(:ran)
    refute :c in tracked(:ran)
  end

  test "empty saga returns the original context" do
    assert {:ok, %{x: 1}} = Saga.new() |> Saga.execute(%{x: 1})
  end

  test "first compensable step failing runs no compensations" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:error, :immediate} end, fn _ -> track(:comp, :a) end)
      |> Saga.execute(%{})

    assert {:error, :a, :immediate, []} = result
    assert tracked(:comp) == []
  end
end
