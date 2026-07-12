# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# BatchDebouncer — a debouncer that accumulates items and flushes them as a batch

Write me an Elixir module called `BatchDebouncer`, implemented as a `GenServer`,
that debounces on a per-key basis but — instead of throwing away all-but-the-last
call — **accumulates the submitted items** during a burst and hands the whole
ordered batch to a handler when the burst settles. This is what you want for
"coalesce a flurry of small writes into one batched flush" (buffered log lines,
batched index updates, grouped notifications).

## Public API

- `BatchDebouncer.start_link(opts)` — starts the process. Accepts a `:name`
  option for registration, defaulting to `BatchDebouncer` when not provided.
  Returns `{:ok, pid}`.

- `BatchDebouncer.call(key, delay_ms, item, handler)` — records `item` (any
  term) under `key` and (re)arms the debounce timer for `delay_ms`. `handler` is
  a **1-arity** function that will eventually receive the list of accumulated
  items. Returns `:ok` promptly and must not block on `handler`. Targets the
  default registered process.

- `BatchDebouncer.pending(key)` — returns the number of items currently buffered
  for `key` (0 if none). Useful for inspection/testing.

## Batch semantics

- **Accumulation, not replacement.** Each `call/4` for a key **appends** its
  `item` to that key's buffer and resets the timer from `delay_ms`. When the
  burst settles (i.e. `delay_ms` elapses with no further calls for that key), the
  handler is invoked **exactly once** with the list of all accumulated items **in
  submission order**.

- **Latest handler wins.** If different calls in the same burst supply different
  handlers, the handler from the **most recent** call is the one invoked (it
  still receives the full ordered batch).

- **The delay is real.** The handler must not run before `delay_ms` has elapsed
  since the most recent `call/4` for that key.

- **Keys are independent.** Each key accumulates and flushes its own batch on its
  own schedule; a burst on one key never mixes items into another.

- **State is cleared after flushing.** Once a key's batch has flushed, its buffer
  is gone and `pending/1` returns 0; a subsequent `call/4` starts a brand-new
  batch.

## Implementation notes

- Use `Process.send_after/3` / `Process.cancel_timer/1` for timers, cancelling
  and re-arming on each call.
- Run `handler` off the server's reduction path (e.g. `spawn`) so a slow or
  crashing handler can't wedge the GenServer. `pending/1` should be a synchronous
  call.
- Accumulate efficiently (e.g. prepend and reverse at flush time) — don't do
  O(n) appends per call.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule BatchDebouncer do
  @moduledoc """
  A `GenServer` that debounces per-key submissions but *accumulates* items during
  a burst and flushes the whole ordered batch to a handler once the burst settles.

  Each `call/4` appends its item and re-arms the key's timer. When `delay_ms`
  elapses with no further calls for the key, the most recently supplied handler
  is invoked exactly once with the list of accumulated items in submission order.
  """

  use GenServer

  @doc """
  Starts the debouncer. Accepts a `:name` option, defaulting to `BatchDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Appends `item` to `key`'s buffer, re-arms the `delay_ms` timer, and remembers
  `handler` (a 1-arity function). Returns `:ok` promptly.
  """
  @spec call(term(), non_neg_integer(), term(), (list() -> any())) :: :ok
  def call(key, delay_ms, item, handler)
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(handler, 1) do
    GenServer.cast(__MODULE__, {:submit, key, delay_ms, item, handler})
  end

  @doc "Returns the number of items currently buffered for `key` (0 if none)."
  @spec pending(term()) :: non_neg_integer()
  def pending(key), do: GenServer.call(__MODULE__, {:pending, key})

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:submit, key, delay_ms, item, handler}, state) do
    # Items are stored reversed (newest first) and reversed at flush time so we
    # never pay O(n) per append.
    items =
      case Map.get(state, key) do
        %{timer: ref, items: items} ->
          Process.cancel_timer(ref)
          [item | items]

        nil ->
          [item]
      end

    ref = Process.send_after(self(), {:flush, key}, delay_ms)
    entry = %{timer: ref, items: items, handler: handler}
    {:noreply, Map.put(state, key, entry)}
  end

  @impl true
  def handle_call({:pending, key}, _from, state) do
    count =
      case Map.get(state, key) do
        %{items: items} -> length(items)
        nil -> 1
      end

    {:reply, count, state}
  end

  @impl true
  def handle_info({:flush, key}, state) do
    case Map.pop(state, key) do
      {%{items: items, handler: handler}, new_state} ->
        batch = Enum.reverse(items)
        spawn(fn -> handler.(batch) end)
        {:noreply, new_state}

      {nil, new_state} ->
        {:noreply, new_state}
    end
  end
end
```

## Failing test report

```
1 of 8 test(s) failed:

  * test pending reflects the buffer size and resets after flush
      
      
      Assertion with == failed
      code:  assert BatchDebouncer.pending("k") == 0
      left:  1
      right: 0
```
