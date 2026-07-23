# Implement the missing function

The specification below is followed by its complete, tested solution —
minus `run`, whose clause bodies are all `# TODO`. Supply that one
function; the rest of the module is fixed and must stay exactly as shown.

## The task

Write me an Elixir module called `WorkStealQueue` that distributes work across N worker processes using a work-stealing algorithm, but with **fault-tolerant, result-tagged** semantics: the `process_fn` you hand it is allowed to blow up (raise, throw, or exit) on some items, and a single bad item must never take down a worker or lose any other item.

I need one primary public function:

- `WorkStealQueue.run(items, worker_count, process_fn)` — takes a list of items, a number of worker processes to spawn, and a one-arity function to apply to each item. Returns a list of `%{item: item, result: tagged_result, worker_id: non_neg_integer}` maps — exactly one per input item, in any order. `process_fn` is applied exactly once to each item (work-stealing must *move* items between workers, never copy them).

**Result tagging:**

- If `process_fn.(item)` returns normally with value `v`, the result field must be `{:ok, v}`. This includes ordinary values that happen to look like errors — e.g. `nil`, an `{:error, ...}` tuple, or an `{:exit, ...}` tuple returned (not raised/thrown/exited) are all tagged `{:ok, v}`.
- If `process_fn.(item)` **raises** an exception, the result field must be `{:error, %{kind: :error, reason: message}}` where `message` is the exception's message string.
- If `process_fn.(item)` **throws** a value `t`, the result field must be `{:error, %{kind: :throw, reason: t}}`.
- If `process_fn.(item)` **exits** with reason `r`, the result field must be `{:error, %{kind: :exit, reason: r}}`. This applies even when `r` is `:normal`.

A failure on one item must NOT prevent the owning worker from continuing with the rest of its queue, and must NOT prevent stealing.

**How it should work internally:**

1. Partition the input list as evenly as possible across `worker_count` workers. Each worker gets a local queue (a list it owns).
2. Spawn all workers as `Task`s. Each worker processes its local queue sequentially, wrapping every `process_fn` call so exceptions/throws/exits are captured and tagged (never propagated).
3. When a worker empties its local queue, it should *steal* work from the busiest worker (the one with the most items remaining). A steal only takes items when the victim has at least two items left: the thief takes the back half of the victim's queue (rounded down), leaving the front half — so a victim down to its last item is never robbed and always processes that item itself. If every other worker's queue is empty, the stealing worker simply exits.
4. Each worker must tag every result with its own `worker_id` (an integer from `0` to `worker_count - 1`).

**Coordination requirements:**

- Workers need a shared coordination mechanism (e.g. an `Agent` or `GenServer`) that tracks each worker's remaining queue so steal attempts can find the busiest worker atomically enough to avoid races. Occasional failed steals (victim emptied first) should be handled gracefully by retrying or moving on.
- `run/3` must be synchronous: block until every item has been processed (successfully or with a captured error) and then return the complete result list.

**Constraints:**
- Use only OTP/stdlib — no external dependencies.
- Must work correctly when `worker_count` is greater than `length(items)`.
- An empty `items` list returns `[]`.
- `process_fn` may be slow or fast — faster workers should naturally pick up slack.

Give me the complete implementation in a single file.

## The module with `run` missing

```elixir
defmodule WorkStealQueue do
  @moduledoc """
  Fault-tolerant, result-tagged work-stealing task queue.

  Distributes work across N worker `Task`s using a work-stealing algorithm.
  Each worker owns a local queue; when it empties it steals the back-half of
  the busiest peer's queue. Coordination goes through an `Agent` whose state is
  a plain map `%{worker_id => [remaining_items]}`, giving each steal attempt an
  atomic snapshot of all queues.

  Unlike a plain work-stealing queue, every `process_fn` invocation is wrapped
  so that raises, throws, and exits are *captured* and turned into a tagged
  `{:error, %{kind: ..., reason: ...}}` result. A misbehaving item can never
  kill its worker or lose sibling items.

  ## Example

      WorkStealQueue.run([1, 2, 3], 2, fn
        2 -> raise "boom"
        n -> n * 10
      end)
      # => [%{item: 1, result: {:ok, 10}, worker_id: 0},
      #     %{item: 2, result: {:error, %{kind: :error, reason: "boom"}}, worker_id: 0},
      #     %{item: 3, result: {:ok, 30}, worker_id: 1}]   (order varies)
  """

  @type tagged_result :: {:ok, any()} | {:error, %{kind: :error | :throw | :exit, reason: any()}}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Process every item by applying `process_fn` across `worker_count` parallel,
  fault-tolerant workers. Returns one result map per item (any order). Blocks
  until all items have been processed.
  """
  @spec run(list(), pos_integer(), (any() -> any())) :: [
          %{item: any(), result: tagged_result(), worker_id: non_neg_integer()}
        ]
  def run(items, worker_count, process_fn)
      when is_list(items) and is_integer(worker_count) and worker_count > 0 and
             is_function(process_fn, 1) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Worker logic
  # ---------------------------------------------------------------------------

  defp run_worker(id, coordinator, process_fn) do
    process_local_queue(id, coordinator, process_fn, [])
  end

  defp process_local_queue(id, coordinator, process_fn, acc) do
    case pop_item(id, coordinator) do
      {:ok, item} ->
        result = safe_apply(process_fn, item)
        entry = %{item: item, result: result, worker_id: id}
        process_local_queue(id, coordinator, process_fn, [entry | acc])

      :empty ->
        try_steal(id, coordinator, process_fn, acc)
    end
  end

  # Wrap a single item's processing so raise/throw/exit become tagged results.
  @spec safe_apply((any() -> any()), any()) :: tagged_result()
  defp safe_apply(process_fn, item) do
    try do
      {:ok, process_fn.(item)}
    rescue
      e -> {:error, %{kind: :error, reason: Exception.message(e)}}
    catch
      :throw, value -> {:error, %{kind: :throw, reason: value}}
      :exit, reason -> {:error, %{kind: :exit, reason: reason}}
    end
  end

  defp try_steal(id, coordinator, process_fn, acc) do
    case find_victim(id, coordinator) do
      nil ->
        acc

      victim_id ->
        case steal_half(victim_id, coordinator) do
          [] ->
            try_steal(id, coordinator, process_fn, acc)

          stolen ->
            Agent.update(coordinator, fn state ->
              Map.update(state, id, stolen, fn existing -> stolen ++ existing end)
            end)

            process_local_queue(id, coordinator, process_fn, acc)
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Coordinator operations
  # ---------------------------------------------------------------------------

  @spec pop_item(non_neg_integer(), pid()) :: {:ok, any()} | :empty
  defp pop_item(id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      case Map.fetch!(state, id) do
        [] -> {:empty, state}
        [head | tail] -> {{:ok, head}, Map.put(state, id, tail)}
      end
    end)
  end

  @spec find_victim(non_neg_integer(), pid()) :: non_neg_integer() | nil
  defp find_victim(thief_id, coordinator) do
    Agent.get(coordinator, fn state ->
      state
      |> Enum.reject(fn {id, queue} -> id == thief_id or queue == [] end)
      |> case do
        [] ->
          nil

        candidates ->
          {victim_id, _queue} = Enum.max_by(candidates, fn {_id, q} -> length(q) end)
          victim_id
      end
    end)
  end

  @spec steal_half(non_neg_integer(), pid()) :: list()
  defp steal_half(victim_id, coordinator) do
    Agent.get_and_update(coordinator, fn state ->
      queue = Map.fetch!(state, victim_id)
      len = length(queue)

      if len < 2 do
        {[], state}
      else
        steal_count = div(len, 2)
        keep_count = len - steal_count
        {keep, stolen} = Enum.split(queue, keep_count)
        {stolen, Map.put(state, victim_id, keep)}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Partitioning
  # ---------------------------------------------------------------------------

  @spec partition(list(), pos_integer()) :: [list()]
  defp partition(items, n) do
    total = length(items)
    base_size = div(total, n)
    extras = rem(total, n)

    {chunks, _remaining} =
      Enum.reduce(0..(n - 1), {[], items}, fn i, {acc, rest} ->
        chunk_size = if i < extras, do: base_size + 1, else: base_size
        {chunk, tail} = Enum.split(rest, chunk_size)
        {[chunk | acc], tail}
      end)

    Enum.reverse(chunks)
  end
end
```

Output only `run` (with any `@doc`/`@spec`/`@impl` lines that belong
directly above it) — the single function, not the module.
