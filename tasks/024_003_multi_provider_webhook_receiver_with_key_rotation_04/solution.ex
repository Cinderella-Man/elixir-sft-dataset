defp handle_verified(conn, provider, body, store) do
  case Jason.decode(body) do
    {:ok, %{"id" => event_id} = payload} when is_binary(event_id) ->
      case Store.store_event(store, provider, event_id, payload) do
        {:ok, :created} -> send_json(conn, 200, %{status: "received"})
        {:ok, :duplicate} -> send_json(conn, 200, %{status: "duplicate"})
      end

    {:ok, _decoded} ->
      send_json(conn, 400, %{error: "bad_payload"})

    {:error, _reason} ->
      send_json(conn, 400, %{error: "bad_payload"})
  end
end