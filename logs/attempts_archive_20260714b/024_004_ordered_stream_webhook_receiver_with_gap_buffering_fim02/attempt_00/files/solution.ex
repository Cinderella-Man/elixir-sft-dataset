@doc """
Handles synchronous store operations: delivery and per-stream inspection.
"""
@spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
@impl GenServer
def handle_call({:deliver, event}, _from, %{streams: streams} = state) do
  sid = event.stream_id
  seq = event.sequence
  stream = Map.get(streams, sid, %{last_seq: 0, buffer: %{}, delivered: []})
  %{last_seq: last_seq, buffer: buffer, delivered: delivered} = stream

  cond do
    seq <= last_seq ->
      {:reply, {:ok, :duplicate}, state}

    Map.has_key?(buffer, seq) ->
      {:reply, {:ok, :duplicate}, state}

    seq == last_seq + 1 ->
      {new_last, new_buffer, new_delivered} =
        drain(last_seq, buffer, delivered, %{event | status: :delivered})

      new_stream = %{last_seq: new_last, buffer: new_buffer, delivered: new_delivered}
      {:reply, {:ok, :received}, %{state | streams: Map.put(streams, sid, new_stream)}}

    true ->
      new_stream = %{stream | buffer: Map.put(buffer, seq, %{event | status: :pending})}
      {:reply, {:ok, :buffered}, %{state | streams: Map.put(streams, sid, new_stream)}}
  end
end

@impl GenServer
def handle_call({:last_sequence, sid}, _from, %{streams: streams} = state) do
  {:reply, stream(streams, sid).last_seq, state}
end

@impl GenServer
def handle_call({:delivered_events, sid}, _from, %{streams: streams} = state) do
  {:reply, stream(streams, sid).delivered, state}
end

@impl GenServer
def handle_call({:buffered_sequences, sid}, _from, %{streams: streams} = state) do
  {:reply, streams |> stream(sid) |> Map.fetch!(:buffer) |> Map.keys() |> Enum.sort(), state}
end