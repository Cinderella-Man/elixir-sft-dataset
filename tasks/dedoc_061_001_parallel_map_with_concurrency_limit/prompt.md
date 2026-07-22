# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule ConcurrencyCounter do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, server_opts} =
      case Keyword.pop(opts, :name) do
        {nil, rest} -> {__MODULE__, rest}
        {name, rest} -> {name, rest}
      end

    GenServer.start_link(__MODULE__, %{count: 0, peak: 0}, [{:name, name} | server_opts])
  end

  def increment(server), do: GenServer.call(server, :increment)

  def decrement(server), do: GenServer.call(server, :decrement)

  def peak(server), do: GenServer.call(server, :peak)

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call(:increment, _from, %{count: count, peak: peak} = state) do
    new_count = count + 1
    new_state = %{state | count: new_count, peak: max(new_count, peak)}
    {:reply, new_count, new_state}
  end

  def handle_call(:decrement, _from, %{count: count} = state) do
    new_count = count - 1
    {:reply, new_count, %{state | count: new_count}}
  end

  def handle_call(:peak, _from, %{peak: peak} = state) do
    {:reply, peak, state}
  end
end

defmodule ParallelMap do
  def pmap(collection, func, max_concurrency)
      when is_function(func, 1) and is_integer(max_concurrency) and max_concurrency >= 1 do
    indexed = collection |> Enum.to_list() |> Enum.with_index()
    total = length(indexed)

    if total == 0 do
      []
    else
      # `Task.async` links each task to this process; trap exits so an
      # abnormally exiting task delivers a message instead of killing us,
      # then restore the flag and drain those messages before returning.
      was_trapping? = Process.flag(:trap_exit, true)

      try do
        {seed, queue} = Enum.split(indexed, max_concurrency)

        # running: %{%Task{} => original_index}
        running = Map.new(seed, fn {elem, idx} -> {start_task(func, elem), idx} end)

        pids = Map.new(Map.keys(running), &{&1.pid, true})
        {raw, pids} = collect(running, queue, func, _results = %{}, pids)

        # Reassemble in original order.
        result = Enum.map(0..(total - 1), fn i -> Map.fetch!(raw, i) end)
        Process.flag(:trap_exit, was_trapping?)
        # Drain ONLY our own tasks' exits: a trapping caller may hold
        # unrelated {:EXIT, ...} mail of its own that pmap must not eat.
        flush_exit_messages(pids)
        result
      after
        Process.flag(:trap_exit, was_trapping?)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp start_task(func, elem), do: Task.async(fn -> func.(elem) end)

  # Base case: nothing running and nothing queued.
  defp collect(running, [] = _queue, _func, results, pids) when map_size(running) == 0,
    do: {results, pids}

  # The as-they-finish loop: harvest whatever `Task.yield_many/2` reports in
  # this tick — a normal reply (`{:ok, value}`) or a crash (`{:exit, reason}`,
  # covering raises, abnormal exits, throws and external kills alike) — then
  # refill the freed slots from the queue and go again.
  defp collect(running, queue, func, results, pids) do
    finished =
      running
      |> Map.keys()
      |> Task.yield_many(20)
      |> Enum.filter(fn {_task, res} -> res != nil end)

    case finished do
      [] ->
        collect(running, queue, func, results, pids)

      finished ->
        finished
        |> Enum.reduce({running, queue, results, pids}, fn {task, res}, {run, q, acc, ps} ->
          idx = Map.fetch!(run, task)

          outcome =
            case res do
              {:ok, value} -> value
              {:exit, reason} -> {:error, reason}
            end

          run = Map.delete(run, task)
          acc = Map.put(acc, idx, outcome)

          case q do
            [] ->
              {run, [], acc, ps}

            [{elem, next_idx} | rest] ->
              refill = start_task(func, elem)
              {Map.put(run, refill, next_idx), rest, acc, Map.put(ps, refill.pid, true)}
          end
        end)
        |> then(fn {run, q, acc, ps} -> collect(run, q, func, acc, ps) end)
    end
  end

  # Trapped exits from finished/crashed tasks land in our mailbox; drain
  # exactly THOSE (matched by task pid) so pmap leaves the caller's mailbox
  # as it found it — including any unrelated {:EXIT, ...} a trapping caller
  # was already holding.
  defp flush_exit_messages(pids) do
    receive do
      {:EXIT, pid, _reason} when is_map_key(pids, pid) -> flush_exit_messages(pids)
    after
      0 -> :ok
    end
  end
end
```
