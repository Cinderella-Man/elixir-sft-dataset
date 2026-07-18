# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule NdjsonStreamer do
  def stream(file_path) do
    file_path
    |> File.stream!(:line, [])
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(&decode_line/1)
  end

  def decode_line(line) do
    trimmed = String.trim(line)

    case JSON.decode(trimmed) do
      {:ok, value} -> {:ok, value}
      {:error, _reason} -> {:error, {:invalid_json, trimmed}}
    end
  end
end
```
