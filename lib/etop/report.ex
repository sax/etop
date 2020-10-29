defmodule Etop.Report do
  @moduledoc """
  Etop Reporting Helpers.

  A set of functions to use to parse and process Etop results.

  Example output

  ```
  ===========================================================================================================================
  nonode@nohost                                                                                                      08:22:56
  Load:  cpu     2.9%                      Memory:  total           42812208     binary    197472
         procs     92                               processes       23093664     code    10223211
         runq       0                                atom             512625      ets      791672

  Pid                        Name or Initial Func  Percent     Reds    Memory MssQ      State Current Function
  ---------------------------------------------------------------------------------------------------------------------------
  <0.9.0>                         :erlang.apply/2    47.66   901851    284652    0    waiting :erl_prim_loader.loop/3
  <0.49.0>                        :erlang.apply/2    12.57   237834    163492    0    waiting :code_server.loop/1
  <0.43.0>        :application_controller.start/1     8.13   153862    264396    0    waiting :gen_server.loop/7
  <0.1.0>               :erts_code_purger.start/0     7.44   140798     25848    0    waiting :erts_code_purger.wait_for_request/0
  <0.2.0>     :erts_literal_area_collector.start/     7.11   134526      2688    0    waiting :erts_literal_area_collector.msg_loop/4
  <0.57.0>                    :file_server.init/1     6.18   116917    426596    0    waiting :gen_server.loop/7
  <0.64.0>                        :group.server/3     3.46    65443  10784016    0    waiting :group.more_data/6
  <0.79.0>                       :disk_log.init/2     1.85    34950    197252    0    waiting :disk_log.loop/1
  <0.228.0>                           Etop.init/1     1.77    33584   6781840    0    running Process.info/1
  <0.3.0>     :erts_dirty_process_signal_handler.     1.26    23850      2688    0    waiting :erts_dirty_process_signal_handler.msg_loop/0
  ===========================================================================================================================
  ```
  """
  import Etop.Utils, only: [pad: 2, pad_t: 2]

  alias Etop.{Utils, Chart}

  require Logger
  require IEx

  @cols [15, 35, 8, 13, 9, 4, 10, 30]
  @header [
    "Pid",
    "Name or Initial Func",
    "Percent",
    "Reds",
    "Memory",
    "MsgQ",
    "State",
    "Current Function"
  ]
  @report_width Enum.sum(@cols) + length(@cols)

  @header_str @header
              |> Enum.zip(@cols)
              |> Enum.with_index()
              |> Enum.map(fn {{str, cols}, i} ->
                case i do
                  0 -> String.pad_trailing(str, cols, " ")
                  7 -> str
                  _ -> String.pad_leading(str, cols, " ")
                end
              end)
              |> Enum.join(" ")
  @separator for _ <- 1..@report_width, do: "="
  @separator_dash for _ <- @separator, do: "-"

  %{
    fun: ":disk_log.loop/1",
    memory: 264_300,
    msg_q: 0,
    name: ":disk_log.init/2",
    percent: 1.22,
    pid: '<0.79.0>',
    reds_diff: 38389,
    reductions: 38389,
    state: :waiting
  }

  @sortable ~w(memory msg_q reductions reds_diff state fun name percent pid reds_diff msg_q)a
  @sort_fields ~w(memory msgq reds reds_diff state fun name percent pid reductions_diff message_queue_len)a
  @sort_field_mapper @sort_fields |> Enum.zip(@sortable)

  @exs_template """
  :code.purge(Etop.Agent)
  :code.delete(Etop.Agent)
  defmodule Etop.Agent do
    @name __MODULE__
    def start do
      if Process.whereis(@name), do: stop()
      {:ok, _acc} = Agent.start(fn -> [] end, name: @name)
    end
    def add(item), do: Agent.cast(@name, & [item | &1])
    def stop, do: Agent.stop(@name)
    def get, do: @name |> Agent.get(& &1) |> Enum.reverse()
  end
  # IO.puts "usage: data = Etop.Agent.get()"
  alias Etop.Agent, as: A
  {:ok, acc} = A.start()
  ## The following items as generated by Etop

  """

  @doc """
  Get the column width of the given column number.
  """
  def column_width(n), do: Enum.at(@cols, n)

  @doc """
  Create a report of the given processes list, and summary stats.
  """
  def create_report(list, total, stats) do
    stats
    |> create_summary()
    |> create_details(list, total)
  end

  @doc """
  Get the data loaded by compiling the output exs file.
  """
  def get do
    if function_exported?(Etop.Agent, :get, 0), do: apply(Etop.Agent, :get, []), else: nil
  end

  @doc """
  Helper to create and output the report.

  Output options:

  * print to current leader
  * save text format to file
  * save executable format to exs file
  """
  def handle_report(%{reporting: false} = state) do
    state
  end

  def handle_report(state) do
    %{stats: %{processes: processes, total: total} = stats} = state

    processes
    |> create_report(total, stats)
    |> save_or_print(state)

    state
  end

  @doc """
  Map the given list to the given extract fields.

  ## Examples

      iex> Etop.Report.list([%{a: %{x: 1}, b: 2}, %{a: %{x: 2}, b: 3}], [:a, :x])
      [1, 2]
  """
  def list(entries, fields) when is_list(fields), do: Enum.map(entries, &get_in(&1, fields))

  @doc """
  Map the given list.

  ## Examples

      iex> data = [%{summary: %{a: %{x: 1}, b: 2}}, %{summary: %{a: %{x: 2}, b: 3}}]
      iex> Etop.Report.list(data, :a, :x)
      [1, 2]
  """
  def list(entries, scope, field), do: list(entries, [:summary, scope, field])

  @doc """
  List the cpu usage values.

  ## Examples

      iex> data = [%{summary: %{load: %{cpu: 1}}}, %{summary: %{load: %{cpu: 2}}}]
      iex> Etop.Report.list_cpu(data)
      [1, 2]
  """
  def list_cpu(entries), do: list(entries, :load, :cpu)

  @doc """
  List the memory usage fields.

  ## Examples

      iex> data = [
      ...> %{summary: %{memory: %{total: 2, user: 1}}},
      ...> %{summary: %{memory: %{total: 4, user: 3}}}]
      iex> Etop.Report.list_memory(data)
      [2, 4]

      iex> data = [
      ...> %{summary: %{memory: %{total: 2, user: 1}}},
      ...> %{summary: %{memory: %{total: 4, user: 3}}}]
      iex> Etop.Report.list_memory(data, :user)
      [1, 3]
  """
  def list_memory(entries, field \\ :total), do: list(entries, :memory, field)

  @doc """
  Load the given exs file.
  """
  def load(path \\ "/tmp/etop.exs") do
    try do
      case Code.eval_file(path) do
        {:ok, _} -> get()
        error -> error
      end
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Get the entry with the max load.

  Gets the entries from `Etop.Agent`
  """
  def max do
    with entries when is_list(entries) <- get(),
         do: max(entries)
  end

  @doc """
  Get the entry with the max load from the given entries list.
  """
  def max(entries) do
    max = Enum.max_by(entries, &get_in(&1, [:summary, :load, :cpu]))
    print(max)
    max
  end

  @doc """
  Print a chart of the given data.
  """
  def plot(list, opts \\ []), do: Chart.puts(list, opts)

  @doc """
  Print a chart of the cpu usage.
  """
  def plot_cpu(entries, opts \\ []) do
    labels = list(entries, [:summary, :time])

    entries
    |> list_cpu()
    |> plot(Keyword.merge([y_label_postfix: "%", title: "CPU Utilization", labels: labels], opts))
  end

  @doc """
  Print a chart of the memory usage.
  """
  def plot_memory(entries, opts \\ []) do
    field = opts[:field] || :total

    labels = list(entries, [:summary, :time])

    entries
    |> list(:memory, field)
    |> Enum.map(&(&1 / (1024 * 1024)))
    |> plot(
      Keyword.merge(
        [width: 80, height: 15, y_label_postfix: "MB", title: "Memory Usage", labels: labels],
        opts
      )
    )
  end

  @doc """
  Print a report with default options.

  Prints a single top entry or a list of top entries to leader or the given file.

  See `Etop.Report.print/3` for more details.
  """
  def print(entry), do: print(entry, nil, %{human: true})

  @doc """
  Print a report with defaults.

  See `Etop.Report.print/3` for more details.
  """
  def print(entry, %{file: file} = state) when is_binary(file) or is_nil(file),
    do: print(entry, file, state)

  def print(entry, opts) when is_list(opts),
    do: print(entry, nil, opts)

  @doc """
  Print a report.

  Prints a single top entry or a list of top entries to leader or the given file.

  Options:

  * sort - one of #{inspect(@sort_fields)}
  """
  def print(entries, file, opts) when is_list(entries) do
    if !opts[:sort] || !!@sort_field_mapper[opts[:sort]] do
      Enum.each(entries, &print(&1, file, opts))
    else
      Logger.warn("invalid sort options")
      {:error, :invalid_sort_option}
    end
  end

  def print(%{} = entry, file, opts) do
    if !opts[:sort] || !!@sort_field_mapper[opts[:sort]] do
      []
      |> puts(@separator)
      |> print_summary(entry, opts)
      |> puts("")
      |> puts(@header_str)
      |> puts(@separator_dash)
      |> print_processes(entry, opts)
      |> Enum.reverse()
      |> write_report(file)
    else
      {:error, :invalid_sort_option}
    end
  end

  @doc """
  Save a report in Elixir terms format.

  Saves the report so that it can be later loaded and analyzed.
  """
  def save_exs_report(report, path) do
    exists? = File.exists?(path)

    File.open(path, [:append], fn fp ->
      unless exists?, do: IO.puts(fp, @exs_template)

      IO.puts(fp, [
        "A.add(",
        inspect(report, limit: :infinity),
        ?),
        10
      ])
    end)
  end

  @doc """
  Get the top n entries.
  """
  def top(entries, num) do
    entries
    |> sort_by_load()
    |> Enum.take(num)
  end

  ###############
  # Private

  defp create_details(report, list, total) do
    l2 = column_width(1)

    items =
      list
      |> Enum.reduce([], fn {pid, reds}, acc ->
        diff = reds.reductions_diff

        try do
          percent = Float.round(diff / total * 100, 2)

          item = %{
            pid: :erlang.pid_to_list(pid),
            name: name_or_initial_fun(reds, l2),
            percent: percent,
            reductions: reds.reductions,
            reds_diff: diff,
            memory: reds.memory,
            msg_q: reds.message_queue_len,
            state: reds.status,
            fun: format_fun(reds.current_function)
          }

          [item | acc]
        rescue
          e ->
            IO.inspect(e)
            IO.inspect(%{diff: diff, reds: reds, total: total}, label: "Bad result")
            acc
        end
      end)
      |> Enum.reverse()

    Map.put(report, :processes, items)
  end

  defp create_summary(stats) do
    time = Utils.local_time() |> NaiveDateTime.to_time() |> to_string()
    cpu = if stats.load, do: stats.load.total, else: "-"

    %{
      summary: %{
        node: stats.node,
        time: time,
        load: %{
          cpu: cpu,
          nprocs: stats.nprocs,
          runq: stats.runq
        },
        memory: stats.memory
      }
    }
  end

  defp dict_initial_call(%{dictionary: dict}) when is_list(dict), do: dict[:"$initial_call"]
  defp dict_initial_call(_), do: nil

  defp format_fun({mod, fun, arity}), do: "#{inspect(mod)}.#{fun}/#{arity}"
  defp format_fun(str) when is_binary(str), do: str
  defp format_fun(_), do: ""

  defp name_or_initial_fun(reds, l2) do
    reds[:registerd_name]
    |> case do
      nil -> format_fun(dict_initial_call(reds) || reds[:initial_call])
      name when is_atom(name) -> name
    end
    |> to_string()
    |> String.replace(~r/^Elixir\./, "")
    |> String.slice(0, l2)
  end

  defp humanize(number, true) do
    Utils.size_string_b(number, 0)
  end

  defp humanize(number, _) do
    to_string(number)
  end

  defp print_processes(report, entry, opts) do
    [l1, l2, l3, l4, l5, l6, l7, _l8] = @cols

    entry.processes
    |> sort_processes(opts[:sort])
    |> Enum.reduce(report, fn p, report ->
      try do
        puts(
          report,
          Enum.join(
            [
              pad_t(p.pid, l1),
              pad(p.name, l2),
              pad(p.percent, l3),
              pad(p.reds_diff, l4),
              p.memory |> humanize(opts[:human]) |> pad(l5),
              pad(p.msg_q, l6),
              pad(p.state, l7),
              p.fun
            ],
            " "
          )
        )
      rescue
        e ->
          Logger.warn(inspect(e))
          Logger.warn("Bad result: " <> inspect(p))
          report
      end
    end)
    |> puts(@separator)
    |> puts("")
  end

  defp print_summary(report, %{summary: summary}, opts) do
    load = summary.load
    memory = summary.memory
    h = opts[:human]

    node = summary.node
    node_len = String.length(node)

    report
    |> puts(node <> pad(summary.time, @report_width - node_len))
    |> summary_line(
      "Load:  cpu  ",
      to_string(load.cpu) <> "%",
      "Memory:  total    ",
      humanize(memory.total, h),
      "     binary",
      humanize(memory.binary, h)
    )
    |> summary_line(
      "       procs",
      load.nprocs,
      "processes",
      humanize(memory.processes, h),
      "     code",
      humanize(memory.code, h)
    )
    |> summary_line(
      "       runq ",
      load.runq,
      "atom    ",
      humanize(memory.atom, h),
      "      ets",
      humanize(memory.ets, h)
    )
  end

  defp puts(report, string) do
    ["\n", string | report]
  end

  defp save_or_print(report, %{format: :exs, file: path}) when is_binary(path),
    do: save_exs_report(report, path)

  defp save_or_print(report, state),
    do: print(report, state)

  defp sort_by_load(entries, sorter \\ &>/2) do
    Enum.sort_by(entries, &get_in(&1, [:summary, :load, :cpu]), sorter)
  end

  defp sort_processes(list, nil), do: list

  defp sort_processes(list, field) do
    field = @sort_field_mapper[field]
    Utils.sort(list, field, secondary: :reds_diff, mapper: & &1)
  end

  defp summary_line(report, load_label, load, mem1_label, mem1, mem2_label, mem2) do
    puts(
      report,
      load_label <>
        pad(load, 7) <>
        pad(mem1_label, 40) <> pad(mem1, 15) <> pad_t(mem2_label, 11) <> pad(mem2, 10)
    )
  end

  defp write_report(report, path) when is_binary(path) do
    case File.write(path, report, [:append]) do
      :ok -> :ok
      error -> Logger.warn("Could not write to #{path}, error: #{inspect(error)}")
    end
  end

  defp write_report(report, _) do
    IO.puts(report)
  end
end
