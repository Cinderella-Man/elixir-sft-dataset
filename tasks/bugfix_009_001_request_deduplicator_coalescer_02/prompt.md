# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

Write me an Elixir GenServer module called `Dedup` that deduplicates concurrent identical requests so that only one execution happens per key at a time.

I need these functions in the public API:

- `Dedup.start_link(opts)` to start the process. It should accept a `:name` option for process registration.

- `Dedup.execute(server, key, func)` where `func` is a zero-arity function. If no execution is currently in flight for the given `key`, the function is executed (asynchronously, so the GenServer isn't blocked) and the caller blocks until the result is ready. If another caller calls `execute` with the same key while the first execution is still running, it does **not** call `func` again — instead it blocks and waits for the already-in-flight execution to finish. Once the function completes, **all** waiting callers receive the same result and the key is cleared so future calls with that key will trigger a fresh execution.

- If `func` raises an exception or returns `{:error, reason}`, all waiting callers should receive the error. Specifically: if `func` raises, every caller gets `{:error, {:exception, exception}}` returned. If `func` returns `{:error, reason}`, every caller gets that `{:error, reason}` as-is. If `func` returns `{:ok, value}` or any other non-error term, every caller gets `{:ok, value}` (wrap plain values in `{:ok, value}` if they aren't already an ok-tuple). After either success or failure, the key must be cleared so subsequent calls trigger a new execution.

The GenServer should not execute `func` inside `handle_call` directly — spawn a task or use `Task.async` so the GenServer remains responsive to new callers registering on the same or different keys while a function is running.

Keep track of waiting callers using a list of `GenServer.from()` references so you can reply to all of them when the result arrives.

Give me the complete module in a single file. Use only OTP standard library, no external dependencies.

## The buggy module

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
  def execute(server, key, func) when is_function(func, 1) do
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

## Failing test report

```
12 of 12 test(s) failed:

  * test executes the function and returns the result
      no function clause matching in Dedup.execute/3

  * test wraps plain return values in an ok tuple
      no function clause matching in Dedup.execute/3

  * test passes through {:error, reason} as-is
      no function clause matching in Dedup.execute/3

  * test concurrent calls with the same key execute the function exactly once
      {:EXIT, #PID<0.213.0>}: {:function_clause, [{Dedup, :execute, [#PID<0.214.0>, "same_key", #Function<3.31585721/0 in DedupTest."test concurrent calls with the same key execute the function exactly once"/1>], [file: ~c".gen_staging/bugfix_009_001_request_deduplicator_coalescer_02_mutant.ex", line: 63]}, {Task.Supervised, :invoke_mfa, 2, [file: ~c"lib/task/supervised.ex", line: 105]}, {Task.Supervised, :reply, 4, [file: ~c"lib/task/supervised.ex", line: 40]}]}

  (…8 more)
```
