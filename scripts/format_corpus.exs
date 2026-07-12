#!/usr/bin/env elixir
# format_corpus.exs — R6: canonical-format status/apply for the task corpus.
#
#   elixir scripts/format_corpus.exs [--apply] [--check] [--only "glob1,glob2"] [--category c1,c2]
#
#   --check   report-only like the default, but exit 1 when anything deviates —
#             the CI / pre-push style gate.
#
# Canonical form = `Code.format_string!/1` output under the pinned toolchain
# (.tool-versions — the formatter's output changes across Elixir versions).
#
# Categories (per file, derived from the dir shape):
#   harness    tasks/*/test_harness.exs — whole-file format
#   module     solution.ex of _01 / wt_ / repair_ / bugfix_ dirs (full modules;
#              a bugfix prompt's buggy fence is captured mutant data — excluded)
#   bundle     multifile solution.ex (<file path="…"> blocks) — each part formatted
#              in place; everything outside the block bodies is byte-preserved
#   fragment   solution.ex of FIM (_0N) and tfim_ dirs — a bare function / test
#              block, possibly indented: dedent → format → re-indent, preserving
#              the original base indentation and trailing-newline convention
#   manifest   tasks/*/manifest.exs
#   embeds     ```elixir fences inside prompt.md of fim/tfim/wt_ dirs; a fence that
#              does not parse (iex> transcripts, pseudo-code) is left untouched.
#              _01 prompts are EXCLUDED on purpose: the blind-screen ledger
#              (logs/screen_blind.jsonl) is keyed by sha256(prompt.md) — cosmetic
#              churn there would force a full ~$58 re-screen. repair_ prompts are
#              excluded too: their broken-code fence is captured attempt data.
#
# Consumers verified formatting-safe before this script existed (see docs/10 R6):
# eval-time FIM/tfim reconstruction is line-based on `# TODO` markers + def/end
# lines (all formatter-preserved) and never byte-compares against the parent;
# `build_skeleton`'s verbatim-in-parent constraint is generation-time only.
#
# Without --apply: report only (counts per category + first deviating files).
# With --apply: rewrite deviating files. Re-run to confirm 0 deviations.

defmodule FormatCorpus do
  @moduledoc false

  @fence ~r/```elixir\n(.*?)\n```/s
  @bundle_block ~r/(<file path="[^"]+">\n)(.*?)(\n<\/file>)/s

  def main(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [apply: :boolean, check: :boolean, only: :string, category: :string]
      )

    apply? = opts[:apply] || false
    check? = opts[:check] || false
    globs = if opts[:only], do: String.split(opts[:only], ","), else: nil
    cats = if opts[:category], do: Enum.map(String.split(opts[:category], ","), &String.to_atom/1)

    files =
      Path.wildcard("tasks/*")
      |> Enum.filter(&File.dir?/1)
      |> Enum.filter(&selected?(&1, globs))
      |> Enum.sort()
      |> Enum.flat_map(&dir_files/1)
      |> Enum.filter(fn {cat, _} -> cats == nil or cat in cats end)

    results =
      files
      |> Task.async_stream(fn {cat, path} -> {cat, path, check(cat, path)} end,
        max_concurrency: System.schedulers_online(),
        timeout: 60_000,
        ordered: true
      )
      |> Enum.map(fn {:ok, r} -> r end)

    deviating = report(results, apply?, check?)
    if check? and deviating > 0, do: System.halt(1)
  end

  defp selected?(_dir, nil), do: true

  defp selected?(dir, globs) do
    base = Path.basename(dir)
    Enum.any?(globs, &match_glob?(base, &1))
  end

  defp match_glob?(name, glob) do
    re = glob |> Regex.escape() |> String.replace("\\*", ".*")
    Regex.match?(~r/^#{re}$/, name)
  end

  # ---------------------------------------------------------------------------
  # Dir shape → the files it contributes, with their categories
  # ---------------------------------------------------------------------------

  defp dir_files(dir) do
    base = Path.basename(dir)
    shape = dir_shape(base)

    sol = Path.join(dir, "solution.ex")
    harness = Path.join(dir, "test_harness.exs")
    manifest = Path.join(dir, "manifest.exs")
    prompt = Path.join(dir, "prompt.md")

    List.flatten([
      if(File.regular?(harness), do: [{:harness, harness}], else: []),
      if(File.regular?(manifest), do: [{:manifest, manifest}], else: []),
      solution_entry(shape, sol),
      if(shape in [:fim_child, :tfim, :wt] and File.regular?(prompt),
        do: [{:embeds, prompt}],
        else: []
      )
    ])
  end

  defp solution_entry(shape, sol) do
    cond do
      not File.regular?(sol) -> []
      shape in [:fim_child, :tfim] -> [{:fragment, sol}]
      shape == :bugfix -> [{:module, sol}]
      String.contains?(File.read!(sol), "<file path=") -> [{:bundle, sol}]
      true -> [{:module, sol}]
    end
  end

  defp dir_shape(base) do
    cond do
      String.starts_with?(base, "repair_") -> :repair
      # bugfix solutions are full modules (parent copies); their prompts carry
      # an INTENTIONALLY buggy fence (captured one-line mutant) that must never
      # be reformatted — same policy as repair_ broken-code fences.
      String.starts_with?(base, "bugfix_") -> :bugfix
      String.starts_with?(base, "wt_") -> :wt
      String.starts_with?(base, "tfim_") -> :tfim
      Regex.match?(~r/_01$/, base) -> :parent
      Regex.match?(~r/_\d\d$/, base) -> :fim_child
      true -> :other
    end
  end

  # ---------------------------------------------------------------------------
  # Canonical form per category
  # ---------------------------------------------------------------------------

  defp check(cat, path) do
    orig = File.read!(path)

    case canonical(cat, orig) do
      {:ok, ^orig} -> :canonical
      {:ok, formatted} -> {:deviates, formatted}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Full files are canonical only when they end with exactly one newline (the
  # `mix format` convention — tasks/**/*.exs is in .formatter.exs inputs, so the two
  # tools must agree). Fragments keep their own trailing convention: they are
  # spliced into reconstructions, not read as standalone files.
  defp canonical(cat, orig) when cat in [:harness, :module, :manifest] do
    {:ok, fmt(orig) |> String.trim_trailing("\n") |> Kernel.<>("\n")}
  end

  defp canonical(:fragment, orig) do
    lines = String.split(orig, "\n")

    base =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn l -> byte_size(l) - byte_size(String.trim_leading(l, " ")) end)
      |> Enum.min(fn -> 0 end)

    indent = String.duplicate(" ", base)

    dedented =
      lines
      |> Enum.map(fn l ->
        if String.trim(l) == "", do: "", else: String.replace_prefix(l, indent, "")
      end)
      |> Enum.join("\n")

    # The re-indent below adds `base` columns to every line, so the formatter must
    # target a correspondingly narrower width or a just-fits line lands over 98 at
    # its embedded indentation (bit on tfim_104_004_04).
    formatted =
      dedented
      |> fmt(line_length: 98 - base)
      |> String.split("\n")
      |> Enum.map(fn l -> if l == "", do: "", else: indent <> l end)
      |> Enum.join("\n")

    {:ok, keep_trailing(formatted, orig)}
  end

  defp canonical(:bundle, orig) do
    out =
      Regex.replace(@bundle_block, orig, fn whole, open, body, close ->
        if formattable_part?(open) do
          open <> String.trim_trailing(fmt(body), "\n") <> close
        else
          whole
        end
      end)

    {:ok, String.trim_trailing(out, "\n") <> "\n"}
  end

  defp canonical(:embeds, orig) do
    out =
      Regex.replace(@fence, orig, fn whole, body ->
        case Code.string_to_quoted(body) do
          {:ok, _} -> "```elixir\n" <> String.trim_trailing(fmt(body), "\n") <> "\n```"
          {:error, _} -> whole
        end
      end)

    {:ok, out}
  end

  defp formattable_part?(open) do
    case Regex.run(~r/path="([^"]+)"/, open) do
      [_, path] -> String.ends_with?(path, [".ex", ".exs"])
      _ -> false
    end
  end

  defp fmt(src, opts \\ []), do: src |> Code.format_string!(opts) |> IO.iodata_to_binary()

  defp keep_trailing(formatted, orig) do
    formatted = String.trim_trailing(formatted, "\n")
    if String.ends_with?(orig, "\n"), do: formatted <> "\n", else: formatted
  end

  # ---------------------------------------------------------------------------
  # Reporting / applying
  # ---------------------------------------------------------------------------

  defp report(results, apply?, check?) do
    by_cat = Enum.group_by(results, fn {cat, _, _} -> cat end)

    IO.puts("=== FORMAT STATUS (canonical = Code.format_string! on this toolchain) ===\n")

    total_dev =
      for cat <- [:harness, :module, :bundle, :fragment, :manifest, :embeds],
          rows = by_cat[cat] || [],
          rows != [],
          reduce: 0 do
        acc ->
          dev = Enum.filter(rows, &match?({_, _, {:deviates, _}}, &1))
          err = Enum.filter(rows, &match?({_, _, {:error, _}}, &1))

          IO.puts(
            "#{String.pad_trailing(to_string(cat), 9)} #{String.pad_leading(to_string(length(dev)), 5)} deviating / #{String.pad_leading(to_string(length(rows)), 5)}" <>
              if(err == [], do: "", else: "   ERRORS: #{length(err)}")
          )

          for {_, path, {:error, reason}} <- Enum.take(err, 5) do
            IO.puts("    ERROR #{path}: #{String.slice(reason, 0, 120)}")
          end

          if apply? do
            for {_, path, {:deviates, formatted}} <- dev, do: File.write!(path, formatted)
          else
            for {_, path, _} <- Enum.take(dev, 3), do: IO.puts("    e.g. #{path}")
          end

          acc + length(dev)
      end

    errors = Enum.count(results, &match?({_, _, {:error, _}}, &1))

    suffix =
      cond do
        apply? -> " — APPLIED (deviating files rewritten)"
        check? -> " — GATE (--check: exits 1 when anything deviates; --apply to rewrite)"
        true -> " (report only; --apply to rewrite)"
      end

    IO.puts("\ntotal: #{total_dev} deviating, #{errors} errors" <> suffix)

    if errors > 0, do: System.halt(1)
    total_dev
  end
end

FormatCorpus.main(System.argv())
