defp wait_for_notification(conn, timeout) do
  receive do
    {:notification, payload} ->
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, Jason.encode!(payload))
  after
    timeout ->
      send_resp(conn, 204, "")
  end
end