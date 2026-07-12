# Fix the bug

The module below was written for the task that follows, but ONE behavior bug
slipped in. The test suite (not shown) fails with the report at the bottom.
Find the bug and fix it — change as little as possible; do not restructure
working code. Reply with the complete corrected module.

## The task the module implements

# EdgeDebouncer — a GenServer debouncer with leading / trailing / both edges

Write me an Elixir module called `EdgeDebouncer`, implemented as a `GenServer`,
that debounces function calls on a per-key basis with a configurable **firing
edge** — the classic trailing-edge debounce, a leading-edge debounce that fires
immediately, or **both** edges (fire on the way in *and* on the way out of a
burst). This mirrors the `leading`/`trailing` options you find in libraries like
lodash's `debounce`.

## Public API

- `EdgeDebouncer.start_link(opts)` — starts the process. It should accept a
  `:name` option for process registration, defaulting to `EdgeDebouncer` (the
  module name) when not provided. Return the usual `{:ok, pid}`.

- `EdgeDebouncer.call(key, delay_ms, func, opts \\ [])` — schedules/handles
  `func` (a zero-arity function) for `key`. `opts` accepts `:edge`, one of
  `:trailing` (default), `:leading`, or `:both`. `key` can be any term. This
  function must return `:ok` and return promptly (it must never block waiting for
  `func` to run). It targets the default registered process (registered under the
  name `EdgeDebouncer`). An invalid `:edge` value should raise `ArgumentError`.

## Edge semantics

A **burst** for a key begins with a `call/4` when that key has no pending timer,
and ends when `delay_ms` elapses with no further calls for that key. Within a
burst each new `call/4` resets the timer (restart from `delay_ms`) and replaces
the pending trailing `func`. The edge is determined by the **first** call that
opens the burst.

- **`:trailing`** — nothing runs on the way in; when the burst settles, only the
  most recently supplied `func` runs, exactly once. (Same behavior as a plain
  debouncer.)

- **`:leading`** — the first call's `func` runs **immediately**. All later calls
  in the burst are coalesced away and never run — no trailing execution occurs.

- **`:both`** — the first call's `func` runs immediately (leading). If — and only
  if — at least one *additional* call arrived during the burst, the most recently
  supplied `func` also runs once when the burst settles (trailing). A burst
  consisting of a single call fires leading only (never twice).

Other rules:

- **The delay is real.** Trailing executions must not run before `delay_ms` has
  elapsed since the most recent `call/4` for that key.
- **Keys are independent.** A pending debounce on one key must not affect another.
- **State is cleared after firing.** Once a burst settles, the key's state is
  gone; a subsequent `call/4` starts a brand-new burst (leading fires again).

## Implementation notes

- Use `Process.send_after/3` for the timers and cancel/replace them
  (`Process.cancel_timer/1`) when a key is called again while pending.
- Run `func` off the server's reduction path (e.g. in a spawned process) so a
  slow or crashing `func` can't wedge the GenServer.
- Use only the OTP standard library — no external dependencies.

Give me the complete module in a single file.

## The buggy module

```elixir
defmodule EdgeDebouncer do
  @moduledoc """
  A `GenServer` that debounces zero-arity function calls on a per-key basis with
  a configurable firing edge: `:trailing` (default), `:leading`, or `:both`.

  A *burst* for a key begins with a `call/4` when the key has no pending timer
  and ends after `delay_ms` of quiet. The edge chosen by the first call of the
  burst decides when the function(s) run:

    * `:trailing` — only the most recent func runs, once, after the burst settles.
    * `:leading`  — the first func runs immediately; nothing runs at the end.
    * `:both`     — the first func runs immediately, and if any further calls
      arrived the most recent func also runs once at the end (a lone call fires
      leading only, never twice).
  """

  use GenServer

  @valid_edges [:trailing, :leading, :both]

  @doc """
  Starts the debouncer. Accepts a `:name` option for registration, defaulting to
  `EdgeDebouncer`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc """
  Handles a debounced `func` for `key`. `opts` may include `:edge`
  (`:trailing` | `:leading` | `:both`, default `:trailing`). Returns `:ok`
  promptly. Raises `ArgumentError` for an invalid edge.
  """
  @spec call(term(), non_neg_integer(), (-> any()), keyword()) :: :ok
  def call(key, delay_ms, func, opts \\ [])
      when is_integer(delay_ms) and delay_ms >= 0 and is_function(func, 0) and is_list(opts) do
    edge = Keyword.get(opts, :edge, :trailing)

    unless edge in @valid_edges do
      raise ArgumentError,
            "invalid :edge #{inspect(edge)}, expected one of #{inspect(@valid_edges)}"
    end

    GenServer.cast(__MODULE__, {:debounce, key, delay_ms, func, edge})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:debounce, key, delay_ms, func, edge}, state) do
    case Map.get(state, key) do
      nil ->
        # First call of a new burst: leading edges fire immediately.
        if edge in [:leading, :both], do: run(func)
        ref = Process.send_after(self(), {:fire, key}, delay_ms)
        entry = %{timer: ref, edge: edge, calls: 2, last_func: func}
        {:noreply, Map.put(state, key, entry)}

      %{timer: ref} = entry ->
        Process.cancel_timer(ref)
        new_ref = Process.send_after(self(), {:fire, key}, delay_ms)
        entry = %{entry | timer: new_ref, calls: entry.calls + 1, last_func: func}
        {:noreply, Map.put(state, key, entry)}
    end
  end

  @impl true
  def handle_info({:fire, key}, state) do
    case Map.pop(state, key) do
      {nil, new_state} ->
        {:noreply, new_state}

      {entry, new_state} ->
        cond do
          entry.edge == :trailing -> run(entry.last_func)
          entry.edge == :both and entry.calls > 1 -> run(entry.last_func)
          true -> :ok
        end

        {:noreply, new_state}
    end
  end

  # Run the func off the server's reduction path.
  defp run(func), do: spawn(fn -> func.() end)
end
```

## Failing test report

```
1 of 9 test(s) failed:

  * test both edges with a single call fires leading only (never twice)
      
      
      Unexpectedly received message :solo (which matched :solo)
```
