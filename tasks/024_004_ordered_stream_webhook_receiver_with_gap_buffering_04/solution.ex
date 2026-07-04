defp handle_verified(conn, body, store) do
  case Jason.decode(body) do
    {:ok, %{"id" => id, "stream_id" => sid, "sequence" => seq} = payload}
    when is_binary(id) and is_binary(sid) and is_integer(seq) ->
      event = %{
        event_id: id,
        stream_id: sid,
        sequence: seq,
        payload: payload,
        status: :pending
      }

      case Store.deliver(store, event) do
        {:ok, :received} -> send_json(conn, 200, %{status: "received"})
        {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
        {:ok, :buffered} -> send_json(conn, 202, %{status: "buffered"})
      end

    {:ok, _decoded} ->
      send_json(conn, 400, %{error: "bad_payload"})

    {:error, _reason} ->
      send_json(conn, 400, %{error: "bad_payload"})
  end
end