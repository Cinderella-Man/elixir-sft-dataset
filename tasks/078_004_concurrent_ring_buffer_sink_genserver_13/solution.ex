  @impl true
  def handle_call({:push, item}, _from, state) do
    {:reply, :ok, do_push(state, item)}
  end

  def handle_call(:to_list, _from, state) do
    {:reply, do_to_list(state), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, state.size, state}
  end

  def handle_call(:peek_oldest, _from, state) do
    {:reply, do_peek_oldest(state), state}
  end

  def handle_call(:peek_newest, _from, state) do
    {:reply, do_peek_newest(state), state}
  end

  def handle_call(:flush, _from, state) do
    {:reply, do_to_list(state), fresh_state(state.capacity)}
  end