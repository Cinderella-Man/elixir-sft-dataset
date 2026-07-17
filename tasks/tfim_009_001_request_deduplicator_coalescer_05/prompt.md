# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule Dedup do
  @moduledoc """
  A GenServer that deduplicates concurrent identical requests.

  When `execute/3` is called with a key that has no in-flight execution,
  the given function is spawned in a separate task and the caller blocks
  until a result is available.

  If `execute/3` is called with a key that already has an in-flight
  execution, the new caller is queued and will receive the same result
  as all other waiters — without triggering a second execution of `func`.

  Once the task finishes (successfully or not), every waiting caller
  receives the result and the key is cleared, so the next call for that
  key starts a fresh execution.

  ## Result normalisation

  | `func` outcome              | What all callers receive          |
  |-----------------------------|-----------------------------------|
  | Returns `{:ok, value}`      | `{:ok, value}`                    |
  | Returns any other term `v`  | `{:ok, v}`                        |
  | Returns `{:error, reason}`  | `{:error, reason}`                |
  | Raises an exception `e`     | `{:error, {:exception, e}}`       |

  ## Example

      {:ok, _pid} = Dedup.start_link(name: MyDedup)

      # Both callers share a single execution of the slow function.
      Task.async(fn -> Dedup.execute(MyDedup, :my_key, fn -> expensive() end) end)
      Task.async(fn -> Dedup.execute(MyDedup, :my_key, fn -> expensive() end) end)
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the `Dedup` GenServer.

  Accepts all standard `GenServer.start_link/3` options, notably `:name`
  for process registration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

  @doc """
  Executes `func` for the given `key`, deduplicating concurrent calls.

  Blocks the caller until the result is ready (no timeout is imposed;
  pass the call through a `Task` if you need a timeout on the caller's
  side).

  Returns `{:ok, value}` on success or `{:error, reason}` on failure.
  """
  @spec execute(GenServer.server(), term(), (-> term())) ::
          {:ok, term()} | {:error, term()}
  def execute(server, key, func) when is_function(func, 0) do
    GenServer.call(server, {:execute, key, func}, :infinity)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  # State shape:
  #   %{key => [GenServer.from()]}
  #
  # A key is present in the map if and only if a task is currently running
  # for it. The value is the (non-empty) list of callers waiting for the
  # result, in arrival order.

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:execute, key, func}, from, state) do
    case Map.fetch(state, key) do
      # -----------------------------------------------------------------------
      # No in-flight execution for this key — spawn one and register caller.
      # -----------------------------------------------------------------------
      :error ->
        parent = self()

        Task.start(fn ->
          result =
            try do
              case func.() do
                {:ok, _} = ok -> ok
                {:error, _} = err -> err
                other -> {:ok, other}
              end
            rescue
              exception -> {:error, {:exception, exception}}
            end

          send(parent, {:task_done, key, result})
        end)

        {:noreply, Map.put(state, key, [from])}

      # -----------------------------------------------------------------------
      # Execution already in flight — join the wait list, do not call func.
      # -----------------------------------------------------------------------
      {:ok, callers} ->
        {:noreply, Map.put(state, key, callers ++ [from])}
    end
  end

  @impl GenServer
  def handle_info({:task_done, key, result}, state) do
    # Pop the callers list and reply to every one of them with the same result.
    {callers, new_state} = Map.pop(state, key, [])
    Enum.each(callers, &GenServer.reply(&1, result))
    {:noreply, new_state}
  end

  # Ignore any other messages (e.g. stray task EXIT signals).
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule DedupTest do
  use ExUnit.Case, async: false

  setup do
    {:ok, pid} = Dedup.start_link([])
    %{dd: pid}
  end

  # -------------------------------------------------------
  # Basic execution
  # -------------------------------------------------------

  test "executes the function and returns the result", %{dd: dd} do
    assert {:ok, 42} = Dedup.execute(dd, "k", fn -> {:ok, 42} end)
  end

  test "wraps plain return values in an ok tuple", %{dd: dd} do
    assert {:ok, "hello"} = Dedup.execute(dd, "k", fn -> "hello" end)
  end

  test "passes through {:error, reason} as-is", %{dd: dd} do
    assert {:error, :boom} = Dedup.execute(dd, "k", fn -> {:error, :boom} end)
  end

  # -------------------------------------------------------
  # Deduplication — the core behaviour
  # -------------------------------------------------------

  test "concurrent calls with the same key execute the function exactly once", %{dd: dd} do
    # TODO
  end

  test "different keys execute independently and concurrently", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(counter, &(&1 + 1))
      Process.sleep(100)
      {:ok, :done}
    end

    tasks =
      for i <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "key:#{i}", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:ok, :done}))
    # Each distinct key triggers its own execution
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Key clearing after completion
  # -------------------------------------------------------

  test "key is cleared after successful execution, allowing a fresh call", %{dd: dd} do
    assert {:ok, 1} = Dedup.execute(dd, "k", fn -> {:ok, 1} end)
    # Second call should trigger a new execution, not return stale data
    assert {:ok, 2} = Dedup.execute(dd, "k", fn -> {:ok, 2} end)
  end

  test "key is cleared after error, allowing a fresh call", %{dd: dd} do
    assert {:error, :fail} = Dedup.execute(dd, "k", fn -> {:error, :fail} end)
    # Key is cleared, so this should trigger a new execution
    assert {:ok, :recovered} = Dedup.execute(dd, "k", fn -> {:ok, :recovered} end)
  end

  # -------------------------------------------------------
  # Error broadcasting
  # -------------------------------------------------------

  test "error result is broadcast to all waiting callers", %{dd: dd} do
    func = fn ->
      Process.sleep(200)
      {:error, :something_went_wrong}
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "err_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, &(&1 == {:error, :something_went_wrong}))
  end

  test "exception in func is broadcast as {:error, {:exception, _}}", %{dd: dd} do
    func = fn ->
      Process.sleep(100)
      raise "kaboom"
    end

    tasks =
      for _ <- 1..5 do
        Task.async(fn -> Dedup.execute(dd, "raise_key", func) end)
      end

    results = Task.await_many(tasks, 5_000)

    assert Enum.all?(results, fn
             {:error, {:exception, %RuntimeError{message: "kaboom"}}} -> true
             _ -> false
           end)
  end

  # -------------------------------------------------------
  # GenServer responsiveness
  # -------------------------------------------------------

  test "GenServer is not blocked while a function is running", %{dd: dd} do
    # Start a slow execution on key "slow"
    slow_task =
      Task.async(fn ->
        Dedup.execute(dd, "slow", fn ->
          Process.sleep(500)
          {:ok, :slow_result}
        end)
      end)

    # Give it a moment to start
    Process.sleep(50)

    # A call on a different key should return quickly, not block
    {elapsed, result} =
      :timer.tc(fn ->
        Dedup.execute(dd, "fast", fn -> {:ok, :fast_result} end)
      end)

    assert result == {:ok, :fast_result}
    # Should be well under 500ms — the GenServer isn't blocked
    # microseconds
    assert elapsed < 200_000

    # Clean up
    Task.await(slow_task, 5_000)
  end

  # -------------------------------------------------------
  # Rapid sequential reuse of the same key
  # -------------------------------------------------------

  test "sequential calls on the same key each trigger their own execution", %{dd: dd} do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    for _ <- 1..5 do
      Dedup.execute(dd, "seq", fn ->
        Agent.update(counter, &(&1 + 1))
        {:ok, :done}
      end)
    end

    # Each sequential call should have executed the function
    assert Agent.get(counter, & &1) == 5
  end

  # -------------------------------------------------------
  # Mixed keys concurrent stress test
  # -------------------------------------------------------

  test "mixed concurrent calls on several keys", %{dd: dd} do
    {:ok, counters} = Agent.start_link(fn -> %{} end)

    tasks =
      for key <- ["a", "b", "c"], _ <- 1..10 do
        Task.async(fn ->
          Dedup.execute(dd, key, fn ->
            Agent.update(counters, fn map ->
              Map.update(map, key, 1, &(&1 + 1))
            end)

            Process.sleep(150)
            {:ok, key}
          end)
        end)
      end

    results = Task.await_many(tasks, 10_000)

    # All callers for each key should get the same result
    for key <- ["a", "b", "c"] do
      key_results = Enum.filter(results, &(&1 == {:ok, key}))
      assert length(key_results) == 10
    end

    # Each key's function was called exactly once
    counts = Agent.get(counters, & &1)
    assert counts["a"] == 1
    assert counts["b"] == 1
    assert counts["c"] == 1
  end

  test "registers under the :name option and is callable by that name" do
    name = :"dedup_named_#{System.unique_integer([:positive])}"
    {:ok, _pid} = Dedup.start_link(name: name)
    assert {:ok, 7} = Dedup.execute(name, "k", fn -> {:ok, 7} end)
  end

  test "key is cleared after a raised exception, allowing a fresh call", %{dd: dd} do
    assert {:error, {:exception, %RuntimeError{message: "boom"}}} =
             Dedup.execute(dd, "k", fn -> raise "boom" end)

    # The raise is a failure, so the key must be cleared for a fresh run.
    assert {:ok, :after_raise} = Dedup.execute(dd, "k", fn -> {:ok, :after_raise} end)
  end
end
```
