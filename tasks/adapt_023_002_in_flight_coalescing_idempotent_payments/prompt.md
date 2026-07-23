# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule IdempotentPayments do
  @moduledoc """
  A GenServer that simulates an idempotent payment processing system with
  in-memory storage.

  Payments are stored in memory and given sequential ids (`"pay_1"`, `"pay_2"`,
  ...). When an idempotency key is supplied, the response produced for that key
  is cached until `now + ttl_ms`; replaying the key inside that window returns
  the original response verbatim and creates no new payment record. A periodic
  `:cleanup` sweep purges only entries whose expiry has been reached. Payment
  records themselves are never removed.
  """

  use GenServer

  @default_ttl_ms 86_400_000
  @default_cleanup_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the payment server.

  Options:

    * `:clock` — zero-arity function returning the current time in milliseconds
      (default `fn -> System.monotonic_time(:millisecond) end`).
    * `:ttl_ms` — how long idempotency keys are remembered (default 86_400_000).
    * `:cleanup_interval_ms` — how often expired idempotency entries are purged
      (default 60_000). Pass `:infinity` to disable automatic cleanup.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @doc """
  Processes a payment.

  When `idempotency_key` is provided and still cached (its expiry has not been
  reached), returns the exact original response and creates no new record.
  Otherwise the payment is processed, and — when a key was given — the result is
  cached for a fresh TTL window. Missing `:amount`, `:currency` or `:recipient`
  yields `{:error, :invalid_params}`, which is cached like any other response.
  """
  @spec process_payment(GenServer.server(), map(), String.t() | nil) ::
          {:ok, map()} | {:error, :invalid_params}
  def process_payment(server, params, idempotency_key \\ nil) do
    GenServer.call(server, {:process_payment, params, idempotency_key})
  end

  @doc """
  Returns every payment record created so far, in creation order.
  """
  @spec get_payments(GenServer.server()) :: [map()]
  def get_payments(server) do
    GenServer.call(server, :get_payments)
  end

  @doc """
  Looks up a single payment record by its id.
  """
  @spec get_payment(GenServer.server(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_payment(server, id) do
    GenServer.call(server, {:get_payment, id})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    cleanup_interval_ms = Keyword.get(opts, :cleanup_interval_ms, @default_cleanup_interval_ms)

    state = %{
      clock: clock,
      ttl_ms: ttl_ms,
      cleanup_interval_ms: cleanup_interval_ms,
      counter: 0,
      payments: [],
      idempotency_keys: %{}
    }

    schedule_cleanup(cleanup_interval_ms)
    {:ok, state}
  end

  @impl true
  def handle_call({:process_payment, params, key}, _from, state) do
    now = state.clock.()

    case cached(state, key, now) do
      {:hit, response} ->
        {:reply, response, state}

      :miss ->
        {result, state} = do_process(state, params, now)
        state = maybe_cache(state, key, result, now)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call(:get_payments, _from, state) do
    {:reply, Enum.reverse(state.payments), state}
  end

  @impl true
  def handle_call({:get_payment, id}, _from, state) do
    case Enum.find(state.payments, &(&1.id == id)) do
      nil -> {:reply, {:error, :not_found}, state}
      payment -> {:reply, {:ok, payment}, state}
    end
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = state.clock.()

    kept =
      state.idempotency_keys
      |> Enum.filter(fn {_key, {_resp, expiry}} -> expiry > now end)
      |> Map.new()

    schedule_cleanup(state.cleanup_interval_ms)
    {:noreply, %{state | idempotency_keys: kept}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp cached(_state, nil, _now), do: :miss

  defp cached(state, key, now) do
    case Map.get(state.idempotency_keys, key) do
      {response, expiry} when expiry > now -> {:hit, response}
      _ -> :miss
    end
  end

  defp do_process(state, params, now) do
    if valid_params?(params) do
      counter = state.counter + 1
      id = "pay_#{counter}"

      response = %{
        id: id,
        amount: params.amount,
        currency: params.currency,
        recipient: params.recipient,
        status: "completed",
        created_at: now
      }

      state = %{state | counter: counter, payments: [response | state.payments]}
      {{:ok, response}, state}
    else
      {{:error, :invalid_params}, state}
    end
  end

  defp maybe_cache(state, nil, _result, _now), do: state

  defp maybe_cache(state, key, result, now) do
    expiry = now + state.ttl_ms
    %{state | idempotency_keys: Map.put(state.idempotency_keys, key, {result, expiry})}
  end

  defp valid_params?(params) do
    is_map(params) and
      Map.has_key?(params, :amount) and
      Map.has_key?(params, :currency) and
      Map.has_key?(params, :recipient)
  end

  defp schedule_cleanup(interval) do
    if interval != :infinity do
      Process.send_after(self(), :cleanup, interval)
    end
  end
end
```

## New specification

# CoalescingPayments — Specification for an Idempotent Payment System with In-Flight Request Coalescing

## Overview

This document specifies an Elixir GenServer module named `CoalescingPayments` that simulates an idempotent payment processing system backed by in-memory storage **and in-flight request coalescing**. Unlike a plain idempotent endpoint, the defining property here is the concurrency model: when several callers hit the same idempotency key *while the first one is still being processed*, only ONE payment is processed and all the concurrent waiters receive that single shared result.

The implementation must use only the OTP standard library; no external dependencies. The complete module must be delivered in a single file.

## API

### `CoalescingPayments.start_link(opts)`

Starts the process. `opts` is a keyword list; it must default to `[]` so `start_link()` works with no arguments. Options:

- `:clock` — zero-arity function returning current time in milliseconds. Default `fn -> System.monotonic_time(:millisecond) end`. Every timestamp and every TTL comparison in the module must come from this function, so a test clock fully controls time.
- `:ttl_ms` — how long a completed idempotency key is remembered. Default `86_400_000`.
- `:cleanup_interval_ms` — default `60_000`. Schedules a recurring `:cleanup` message via `Process.send_after/3` (scheduled once at init and re-scheduled after each `:cleanup` is handled). The value `:infinity` disables scheduling entirely — no `:cleanup` message is ever sent by the server itself.
- `:processor` — one-arity function receiving `params`, returning `:ok` (payment accepted) or `{:error, reason}` (gateway declined). Simulates the slow external call. Default `fn _params -> :ok end`.
- `:name` — if present, forwarded to `GenServer.start_link/3` as the name registration option. Any other keys in `opts` are ignored.

### `CoalescingPayments.process_payment(server, params, idempotency_key \\ nil)`

`params` is a map expected to have `:amount` (integer cents), `:currency` (string) and `:recipient` (string). The call must use a client-side timeout of 30 seconds (not the default 5 s), since a coalesced caller may wait for a slow processor.

Returns `{:ok, response}` or `{:error, reason}`.

**Validation.** `params` is *valid* only if it is a map that has all three keys `:amount`, `:currency` and `:recipient`. Values are never inspected — no type or range checks; `%{amount: -5, currency: nil, recipient: ""}` is valid. Extra keys are allowed and simply ignored. An invalid `params` yields `{:error, :invalid_params}` immediately, without ever calling the processor:

- with `idempotency_key == nil`: returned, nothing stored;
- with a key: `{:error, :invalid_params}` is also **cached as a completed entry** for that key with the normal TTL, so later calls with the same key return `{:error, :invalid_params}` from cache even if they pass valid params.

**Semantics with `idempotency_key == nil`.** Every call processes a new payment independently — no caching, no coalescing, even for two identical `params` maps. Concurrent nil-key calls each get their own result.

**Semantics with an idempotency key** (any term, typically a string — the key is used as-is as a map key, never inspected):

1. **Completed and not expired** — an entry exists whose expiry is *strictly greater than* the current clock value: return the exact cached result (the same `{:ok, response}` tuple, including the original `:id` and `:created_at`) without re-running the processor. An entry whose expiry is exactly equal to `now` is treated as expired.
2. **Pending (in flight)** — another caller triggered processing for this key and it has not finished: the caller blocks (no reply yet) and is added to the waiter list for that key. When the work finishes, every waiter — including the original caller — receives the same result via `GenServer.reply/2`. The processor runs **exactly once** for the whole group, and only **one** payment record is created. Note that a pending entry short-circuits before validation: a later caller joining a pending key gets the group's result regardless of the `params` it passed, and those params are discarded.
3. **Unseen key, or completed-but-expired key** — validate the params and start fresh processing; an expired entry is simply overwritten.

**Non-blocking requirement.** The GenServer must never block inside the processor. The processor is to be run in a spawned process, which sends the outcome back to the server; the server then replies to all waiting callers with `GenServer.reply/2`. While work is in flight, the server must keep serving other calls (`get_payments/1`, `in_flight_count/1`, other keys, etc.).

**Processor exceptions.** If the processor raises, the spawned worker rescues it and the outcome becomes `{:error, {:exception, message}}` where `message` is `Exception.message/1` of the raised exception. The caller (and any coalesced waiters) get that error tuple; it is cached like any other result when a key was given. The server does not crash.

**Result construction.** When the processor returns `:ok`, the server increments an integer counter (starting at 0) and builds:

- `:id` — `"pay_N"` where N is the new counter value, so the first successful payment is `"pay_1"`, the second `"pay_2"`, and so on. Only *successful* payments consume a counter value; a declined or invalid payment does not.
- `:amount`, `:currency`, `:recipient` — copied from `params`.
- `:status` — always the string `"completed"`.
- `:created_at` — the clock value read at the moment the result is finalized (i.e. when the worker's outcome is handled, not when the request arrived).

The response map is appended to the payment records and returned as `{:ok, response}`. When the processor returns `{:error, reason}`, the caller gets `{:error, reason}` verbatim, no counter is consumed and no payment record is stored.

**Caching of results.** For a keyed request, the result (success *or* error, including gateway declines and processor exceptions) is stored as a completed entry with expiry `clock.() + ttl_ms`, computed when the work finishes. From then on, repeated calls with that key return the cached result until expiry.

### `CoalescingPayments.get_payments(server)`

Returns the list of all payment records **oldest first**. Returns `[]` when none exist. Only successful payments appear here.

### `CoalescingPayments.get_payment(server, id)`

Returns `{:ok, payment}` for a matching `:id`, or `{:error, :not_found}` for any unknown id.

### `CoalescingPayments.in_flight_count(server)`

Returns a non-negative integer: the number of payment requests currently being processed and not yet replied to. This counts both keyed requests in the pending state and nil-key requests still awaiting their worker. A coalesced group of N waiters on one key counts as **1**. The count drops back as each unit of work is finalized, so once everything settles it returns `0`. Requests rejected as `:invalid_params` never enter this count.

## Edge cases

### Cleanup

Payment records are **never** removed — neither by TTL nor by cleanup. The `:cleanup` message only purges idempotency entries that are *completed and expired* (expiry not strictly greater than the current clock). Pending entries are always kept, no matter how long they have been in flight. Cleanup is purely an optimization: an expired entry that has not yet been purged must still behave as expired when a call hits it. Unknown/unexpected messages sent to the server must be ignored without crashing.
