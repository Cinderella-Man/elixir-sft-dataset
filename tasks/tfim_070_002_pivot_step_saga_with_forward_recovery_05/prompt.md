# Complete the blanked test

You get a module and its ExUnit harness, minus the body of ONE `test` —
the `# TODO` marks the spot, and its name says what it must prove. Write
exactly that test so the harness passes against a correct implementation
of the module.

## Module under test

```elixir
defmodule Saga do
  @moduledoc """
  Saga pattern with a **pivot boundary** and **forward recovery**.

  Steps come in two kinds:

    * `:compensable` — added with `step/4`. These precede the commit point
      and can be rolled back by their compensating action.
    * `:retriable` — added with `retriable/4`. These follow the commit point.
      They have no compensation; on failure their action is retried up to
      `max_attempts`, driving the saga *forward* to completion.

  A failing compensable step rolls back previously completed compensable
  steps in reverse order. A retriable step that exhausts its attempts fails
  the saga *without* rolling anything back — the pivot has been crossed and
  committed work is not undone.
  """

  @typedoc "A step action: given the context, returns `{:ok, result}` or `{:error, reason}`."
  @type action :: (map() -> {:ok, term()} | {:error, term()})

  @typedoc "A compensating action: receives the context; its return value is recorded."
  @type compensate :: (map() -> term())

  @typedoc "A saga coordinator."
  @type t :: %__MODULE__{steps: [map()]}

  defstruct steps: []

  @doc "Creates a new, empty saga."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Appends a compensable step (rolled back on an earlier-or-current failure)."
  @spec step(t(), atom(), action(), compensate()) :: t()
  def step(%__MODULE__{} = saga, name, action_fn, compensate_fn)
      when is_atom(name) and is_function(action_fn, 1) and is_function(compensate_fn, 1) do
    entry = %{kind: :compensable, name: name, action: action_fn, compensate: compensate_fn}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Appends a retriable step (retried up to `max_attempts`, never compensated)."
  @spec retriable(t(), atom(), action(), pos_integer()) :: t()
  def retriable(%__MODULE__{} = saga, name, action_fn, max_attempts)
      when is_atom(name) and is_function(action_fn, 1) and is_integer(max_attempts) and
             max_attempts >= 1 do
    entry = %{kind: :retriable, name: name, action: action_fn, max_attempts: max_attempts}
    %__MODULE__{saga | steps: saga.steps ++ [entry]}
  end

  @doc "Executes the saga against an initial context map."
  @spec execute(t(), map()) :: {:ok, map()} | {:error, atom(), term(), keyword()}
  def execute(%__MODULE__{steps: steps}, context) when is_map(context) do
    run(steps, [], context)
  end

  # --- execution -----------------------------------------------------------

  defp run([], _completed, context), do: {:ok, context}

  defp run(
         [%{kind: :compensable, name: name, action: action} = step | rest],
         completed,
         context
       ) do
    case safe(action, context) do
      {:ok, result} ->
        run(rest, [step | completed], Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, reason, compensate_all(completed, context)}
    end
  end

  defp run(
         [%{kind: :retriable, name: name, action: action, max_attempts: max} | rest],
         completed,
         context
       ) do
    case attempt(action, context, max, 1) do
      {:ok, result} ->
        run(rest, completed, Map.put(context, name, result))

      {:error, reason} ->
        {:error, name, {:retries_exhausted, reason}, []}
    end
  end

  defp attempt(action, context, max, n) do
    case safe(action, context) do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        if n >= max, do: {:error, reason}, else: attempt(action, context, max, n + 1)
    end
  end

  defp safe(action, context) do
    case action.(context) do
      {:ok, _} = ok -> ok
      {:error, _} = err -> err
      other -> {:error, {:unexpected_return, other}}
    end
  rescue
    exception -> {:error, {:exception, exception, __STACKTRACE__}}
  end

  # --- compensation --------------------------------------------------------

  defp compensate_all(completed, context) do
    Enum.map(completed, fn %{name: name, compensate: compensate} ->
      {name, safe_compensate(compensate, context)}
    end)
  end

  defp safe_compensate(compensate, context) do
    compensate.(context)
  rescue
    exception -> {:exception, exception, __STACKTRACE__}
  catch
    kind, value -> {:caught, kind, value}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
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
    # TODO
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

  test "a raising compensation early in the reverse chain still lets later ones run and is recorded" do
    result =
      Saga.new()
      |> Saga.step(:a, fn _ -> {:ok, 1} end, fn _ ->
        track(:ran, :a)
        :ca
      end)
      |> Saga.step(:b, fn _ -> {:ok, 2} end, fn _ ->
        track(:ran, :b)
        raise "kaboom in compensation b"
      end)
      |> Saga.step(:c, fn _ -> {:error, :fail} end, fn _ -> track(:ran, :c) end)
      |> Saga.execute(%{})

    assert {:error, :c, :fail, comps} = result
    assert Keyword.keys(comps) == [:b, :a]
    assert Keyword.has_key?(comps, :b)
    assert comps[:a] == :ca
    assert tracked(:ran) == [:b, :a]
  end

  test "retries_exhausted carries the reason from the final attempt, not an earlier one" do
    Process.put(:n, 0)

    result =
      Saga.new()
      |> Saga.retriable(
        :commit,
        fn _ ->
          n = Process.get(:n) + 1
          Process.put(:n, n)
          {:error, {:attempt, n}}
        end,
        3
      )
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, {:attempt, 3}}, []} = result
  end

  test "every retry of a retriable action receives the identical context map" do
    result =
      Saga.new()
      |> Saga.step(:seed, fn _ -> {:ok, :s} end, fn _ -> nil end)
      |> Saga.retriable(
        :commit,
        fn ctx ->
          track(:ctxs, ctx)
          if length(tracked(:ctxs)) < 3, do: {:error, :flaky}, else: {:ok, :done}
        end,
        4
      )
      |> Saga.execute(%{base: 7})

    assert {:ok, _} = result
    seen = tracked(:ctxs)
    assert length(seen) == 3
    assert Enum.uniq(seen) == [%{base: 7, seed: :s}]
  end

  test "retriable rejects a non-positive max_attempts via its guard" do
    saga = Saga.new()

    assert_raise FunctionClauseError, fn ->
      Saga.retriable(saga, :commit, fn _ -> {:ok, :x} end, 0)
    end

    assert_raise FunctionClauseError, fn ->
      Saga.retriable(saga, :commit, fn _ -> {:ok, :x} end, -1)
    end
  end

  test "max_attempts of one performs a single attempt and never retries" do
    Process.put(:once, 0)

    result =
      Saga.new()
      |> Saga.retriable(
        :commit,
        fn _ ->
          Process.put(:once, Process.get(:once) + 1)
          {:error, :nope}
        end,
        1
      )
      |> Saga.execute(%{})

    assert {:error, :commit, {:retries_exhausted, :nope}, []} = result
    assert Process.get(:once) == 1
  end

  test "compensating functions receive the context accumulated up to the failure" do
    result =
      Saga.new()
      |> Saga.step(:a, fn ctx -> {:ok, ctx.init} end, fn ctx ->
        track(:comp_ctx, ctx)
        :ca
      end)
      |> Saga.step(:b, fn _ -> {:ok, :bee} end, fn ctx ->
        track(:comp_ctx, ctx)
        :cb
      end)
      |> Saga.step(:c, fn _ -> {:error, :boom} end, fn _ -> :cc end)
      |> Saga.execute(%{init: :z})

    assert {:error, :c, :boom, [b: :cb, a: :ca]} = result
    assert tracked(:comp_ctx) == [%{init: :z, a: :z, b: :bee}, %{init: :z, a: :z, b: :bee}]
  end
end
```
