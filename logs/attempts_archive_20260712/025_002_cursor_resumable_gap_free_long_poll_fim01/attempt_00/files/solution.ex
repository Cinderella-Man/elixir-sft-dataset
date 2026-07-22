  defp respond_with_events(conn, events) do
    {max_seq, _payload} = List.last(events)
    payloads = Enum.map(events, fn {_seq, payload} -> payload end)
    body = Jason.encode!(%{"cursor" => max_seq, "events" => payloads})

    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("x-notification-cursor", Integer.to_string(max_seq))
    |> send_resp(200, body)
  end