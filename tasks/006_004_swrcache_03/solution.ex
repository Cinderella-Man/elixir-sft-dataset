  defp spawn_revalidate(key, loader) do
    task_ref = make_ref()
    parent = self()

    _ =
      Task.start_link(fn ->
        try do
          new_value = loader.()
          send(parent, {:revalidate_complete, key, task_ref, new_value})
        rescue
          e -> send(parent, {:revalidate_failed, key, task_ref, e})
        catch
          kind, reason -> send(parent, {:revalidate_failed, key, task_ref, {kind, reason}})
        end
      end)

    task_ref
  end