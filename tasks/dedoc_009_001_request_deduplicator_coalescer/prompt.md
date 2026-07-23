# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule Dedup do
  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, %{}, opts)
  end

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
