  defp start_work(processor, params, tag) do
    server = self()

    spawn(fn ->
      outcome =
        try do
          processor.(params)
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        end

      send(server, {:work_done, tag, params, outcome})
    end)
  end