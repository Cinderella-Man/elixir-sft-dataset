  def call(conn, opts) do
    store =
      Map.get(conn.private, :team_store) ||
        Keyword.get(opts, :store, TeamStore)

    with [header] <- get_req_header(conn, "authorization"),
         "Bearer " <> token <- header,
         {:ok, user_id} <- TeamStore.get_user_by_token(store, token) do
      assign(conn, :current_user, user_id)
    else
      _ -> unauthorized(conn)
    end
  end