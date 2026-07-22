@impl GenServer
def handle_call(:now, _from, %{script: script, index: index, policy: policy} = state) do
  len = length(script)

  cond do
    index < len ->
      {:reply, {:ok, Enum.at(script, index)}, %{state | index: index + 1}}

    policy == :repeat_last ->
      {:reply, {:ok, List.last(script)}, state}

    policy == :cycle ->
      {:reply, {:ok, Enum.at(script, rem(index, len))}, %{state | index: index + 1}}

    policy == :raise ->
      {:reply, {:error, :exhausted}, state}
  end
end

def handle_call(:remaining, _from, %{script: script, index: index} = state) do
  {:reply, max(0, length(script) - index), state}
end

def handle_call(:reset, _from, state), do: {:reply, :ok, %{state | index: 0}}

def handle_call({:push, datetimes}, _from, state) do
  {:reply, :ok, %{state | script: state.script ++ datetimes}}
end