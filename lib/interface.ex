defmodule BFF.Interface do
  defp list_item(%{type: :name_x} = item) do
    mode = BFF.Mode.aix_mode(item.contents.mode)
    {itype, _, _, _, _, _} = mode
    mode_str = BFF.Mode.mode_string(mode)
    if item.magic == 60012 do
      IO.puts(:stderr, "WARNING: #{item.contents.name} is packed")
    end
    if itype == :link do
      IO.puts("#{mode_str}\t#{item.contents.uid}\t#{item.contents.gid}\t#{item.contents.mtime}\t#{item.contents.size}\t#{item.contents.name} -> #{item.contents.contents}")
    else
      IO.puts("#{mode_str}\t#{item.contents.uid}\t#{item.contents.gid}\t#{item.contents.mtime}\t#{item.contents.size}\t#{item.contents.name}")
    end
  end

  defp list_item(%{type: :volume} = item) do
    IO.puts(" ** Disk \"#{item.contents.name_disk}\" / Filesystem \"#{item.contents.name_filesystem}\" **")
  end

  defp list_item(:end), do: :ok

  defp list([]), do: :ok

  defp list([item | rest]) do
    list_item(item)
    list(rest)
  end

  def main(argv) do
    # take an archive over stdin
    :io.setopts(:standard_io, encoding: :latin1)
    input = IO.binread(:stdio, :all)
    {parsed, _} = BFF.read_file(input)
    [mode | _to_extract] = argv
    case mode do
      "l" ->
        list(parsed)
      "x" ->
        raise("Not implemented")
    end
  end
end
