#!/usr/bin/env elixir
# fetch_benchmarks.exs — download the public Elixir code benchmarks and normalize
# them into ONE canonical fixture for the decontamination gate (validate.exs
# --decontam). No auth, no paid API — just public HuggingFace + GitHub data.
#
#   mix run scripts/fetch_benchmarks.exs            # fetch (reuse cached downloads)
#   mix run scripts/fetch_benchmarks.exs --force    # re-download everything
#
# Sources (all public, all Elixir subsets):
#   * MultiPL-E  nuprl/MultiPL-E   humaneval-elixir (161) + mbpp-elixir (397)
#                — code-COMPLETION benchmark: prompt is a module stub + docstring,
#                  there is NO reference solution in the dataset, so solution_text
#                  is null for these rows (the prompt is the contamination vector).
#   * McEval     Multilingual-Multimodal-NLP/McEval  generation/Elixir.jsonl (50)
#                — prompt stub + canonical_solution body.
#   * Exercism   github.com/exercism/elixir  practice + concept exercises
#                — .docs/instructions.md (prompt) + .meta/{example,exemplar}.ex.
#
# Output: test/fixtures/benchmarks/benchmarks.jsonl — one JSON object per line,
# normalized to {source, id, prompt_text, solution_text|null}. The FIRST line is a
# machine-readable `_meta` record (generated_at + per-source counts + which
# sources were included / failed). The file is meant to be checked in by the
# orchestrator; it is fully machine-generated.
#
# Idempotent: raw downloads are cached under tmp/benchmarks_cache/ (gitignored);
# a re-run reuses the cache and regenerates the same fixture. --force re-downloads.
# If ONE source fails (URL moved, network blip) the others are still fetched and
# the fixture is written WITHOUT it, with the failure recorded in the _meta line.

# Belt-and-suspenders for a bare `elixir` launch; a no-op under `mix run`.
for pattern <- ["_build/dev/lib/*/ebin", "_build/test/lib/*/ebin"],
    path <- Path.wildcard(pattern),
    do: Code.prepend_path(path)

defmodule FetchBenchmarks do
  @moduledoc false

  @fixture "test/fixtures/benchmarks/benchmarks.jsonl"
  @cache "tmp/benchmarks_cache"

  @multipl_e [
    {"multipl-e:humaneval-elixir",
     "https://huggingface.co/api/datasets/nuprl/MultiPL-E/parquet/humaneval-elixir/test/0.parquet",
     "humaneval-elixir.parquet"},
    {"multipl-e:mbpp-elixir",
     "https://huggingface.co/api/datasets/nuprl/MultiPL-E/parquet/mbpp-elixir/test/0.parquet",
     "mbpp-elixir.parquet"}
  ]

  @mceval_source "mceval:elixir-generation"
  @mceval_url "https://huggingface.co/datasets/Multilingual-Multimodal-NLP/McEval/resolve/main/generation/Elixir.jsonl"
  @mceval_cache "mceval-elixir-generation.jsonl"

  @exercism_source "exercism:elixir-track"
  @exercism_repo "https://github.com/exercism/elixir"
  @exercism_cache "exercism-elixir"

  def main(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [force: :boolean])
    force = opts[:force] || false
    File.mkdir_p!(@cache)

    IO.puts("Fetching public Elixir benchmarks (force=#{force}) ...\n")

    results =
      fetch_multipl_e(force) ++
        [fetch_mceval(force)] ++
        [fetch_exercism(force)]

    {ok, failed} = Enum.split_with(results, & &1.ok)
    records = Enum.flat_map(ok, & &1.rows)

    write_fixture(records, ok, failed)
    report(ok, failed, length(records))
  end

  # ── MultiPL-E (parquet via Explorer) ────────────────────────────────────────

  defp fetch_multipl_e(force) do
    for {source, url, cache_name} <- @multipl_e do
      guard(source, fn ->
        path = Path.join(@cache, cache_name)
        download_binary(url, path, force)
        df = Explorer.DataFrame.from_parquet!(path)

        rows =
          df
          |> Explorer.DataFrame.to_rows()
          |> Enum.map(fn r ->
            # MultiPL-E is a completion benchmark: the prompt is a module stub +
            # docstring examples; there is NO reference solution to normalize, so
            # solution_text is nil. `name` is the stable per-problem id.
            record(source, r["name"], r["prompt"], nil)
          end)

        {source, rows}
      end)
    end
  end

  # ── McEval (jsonl over HTTP) ────────────────────────────────────────────────

  defp fetch_mceval(force) do
    guard(@mceval_source, fn ->
      path = Path.join(@cache, @mceval_cache)
      download_text(@mceval_url, path, force)

      rows =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)
        |> Enum.map(fn r ->
          record(@mceval_source, r["task_id"], r["prompt"], r["canonical_solution"])
        end)

      {@mceval_source, rows}
    end)
  end

  # ── Exercism (shallow git clone) ────────────────────────────────────────────

  defp fetch_exercism(force) do
    guard(@exercism_source, fn ->
      dir = Path.join(@cache, @exercism_cache)
      clone_exercism(dir, force)

      # practice/<slug> keeps .meta/example.ex; concept/<slug> keeps .meta/exemplar.ex.
      # Both keep .docs/instructions.md (the exercise description = the "prompt").
      rows =
        [{"practice", "example.ex"}, {"concept", "exemplar.ex"}]
        |> Enum.flat_map(fn {kind, sol_name} ->
          dir
          |> Path.join("exercises/#{kind}/*")
          |> Path.wildcard()
          |> Enum.filter(&File.dir?/1)
          |> Enum.map(fn ex ->
            slug = Path.basename(ex)
            prompt = read_if(Path.join(ex, ".docs/instructions.md"))
            solution = read_if(Path.join(ex, ".meta/#{sol_name}"))
            record(@exercism_source, "#{kind}/#{slug}", prompt, solution)
          end)
          |> Enum.reject(&(&1["prompt_text"] == "" and is_nil(&1["solution_text"])))
        end)

      {@exercism_source, rows}
    end)
  end

  defp clone_exercism(dir, force) do
    if force, do: File.rm_rf!(dir)

    if File.dir?(Path.join(dir, ".git")) do
      IO.puts("  [#{@exercism_source}] reusing cached clone at #{dir}")
    else
      File.rm_rf!(dir)
      IO.puts("  [#{@exercism_source}] shallow-cloning #{@exercism_repo} ...")

      case System.cmd("git", ["clone", "--depth", "1", @exercism_repo, dir],
             stderr_to_stdout: true
           ) do
        {_out, 0} -> :ok
        {out, code} -> raise "git clone failed (exit #{code}): #{String.slice(out, 0, 400)}"
      end
    end
  end

  # ── shared download helpers ─────────────────────────────────────────────────

  defp download_binary(url, path, force) do
    if not force and File.regular?(path) do
      IO.puts("  reusing cached #{path}")
    else
      IO.puts("  downloading #{url}")
      body = get200!(url, decode_body: false)
      File.write!(path, body)
    end
  end

  defp download_text(url, path, force) do
    if not force and File.regular?(path) do
      IO.puts("  reusing cached #{path}")
    else
      IO.puts("  downloading #{url}")
      body = get200!(url, [])
      text = if is_binary(body), do: body, else: to_string(body)
      File.write!(path, text)
    end
  end

  # A non-200 (a moved/renamed URL) raises a CONCISE message so the failed_sources
  # entry in the fixture stays readable — not the whole Req.Response struct.
  defp get200!(url, opts) do
    case Req.get!(url, [retry: :transient] ++ opts) do
      %{status: 200, body: body} -> body
      %{status: status} -> raise "HTTP #{status} from #{url}"
    end
  end

  # ── normalization + fixture writing ─────────────────────────────────────────

  # One canonical record. prompt_text is always a string (possibly ""); solution
  # is either a non-empty string or nil (JSON null). Keys are strings so the row
  # round-trips through Jason unchanged.
  defp record(source, id, prompt, solution) do
    %{
      "source" => source,
      "id" => to_string(id),
      "prompt_text" => trim_str(prompt),
      "solution_text" => nilify(solution)
    }
  end

  defp trim_str(nil), do: ""
  defp trim_str(s) when is_binary(s), do: s
  defp trim_str(s), do: to_string(s)

  defp nilify(nil), do: nil
  defp nilify(s) when is_binary(s), do: if(String.trim(s) == "", do: nil, else: s)
  defp nilify(s), do: nilify(to_string(s))

  defp write_fixture(records, ok, failed) do
    File.mkdir_p!(Path.dirname(@fixture))

    meta = %{
      "_meta" => true,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "generator" => "scripts/fetch_benchmarks.exs",
      "total_rows" => length(records),
      "sources" => Map.new(ok, &{&1.source, &1.count}),
      "included_sources" => Enum.map(ok, & &1.source),
      "failed_sources" => Enum.map(failed, &%{"source" => &1.source, "error" => &1.error})
    }

    body =
      [meta | records]
      |> Enum.map_join("\n", &Jason.encode!/1)

    File.write!(@fixture, body <> "\n")
  end

  # ── error isolation ─────────────────────────────────────────────────────────

  # Each source is fetched inside `guard/2`: a single source blowing up (URL moved,
  # a parse error) is caught, recorded, and does NOT abort the others.
  defp guard(source, fun) do
    try do
      {^source, rows} = fun.()
      %{ok: true, source: source, count: length(rows), rows: rows, error: nil}
    rescue
      e ->
        %{ok: false, source: source, count: 0, rows: [], error: Exception.message(e)}
    catch
      kind, reason ->
        %{ok: false, source: source, count: 0, rows: [], error: "#{kind}: #{inspect(reason)}"}
    end
  end

  defp read_if(path), do: if(File.regular?(path), do: File.read!(path), else: "")

  defp report(ok, failed, total) do
    IO.puts("\n=== BENCHMARK FIXTURE WRITTEN: #{@fixture} ===")
    IO.puts("  total rows: #{total}")
    IO.puts("  included sources:")
    for s <- ok, do: IO.puts("    - #{s.source}: #{s.count} rows")

    if failed != [] do
      IO.puts("  FAILED sources (fixture written WITHOUT them):")
      for s <- failed, do: IO.puts("    - #{s.source}: #{s.error}")
    else
      IO.puts("  failed sources: none")
    end
  end
end

FetchBenchmarks.main(System.argv())
