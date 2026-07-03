@impl true
def handle_call({:execute, func, opts}, from, state) do
  clock_fn = state.clock
  random_fn = state.random

  spawn_link(fn ->
    result = retry_loop(func, opts, clock_fn, random_fn)
    GenServer.reply(from, result)
  end)

  {:noreply, state}
end