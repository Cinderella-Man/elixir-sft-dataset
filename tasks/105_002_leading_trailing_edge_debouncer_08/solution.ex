  # Run the func off the server's reduction path.
  defp run(func), do: spawn(fn -> func.() end)