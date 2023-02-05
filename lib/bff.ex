defmodule BFF do
  # from AIX dumprestor.h
  @magic 60011
  @packed_magic 60012

  @fs_volume        0
  @fs_end           7
  @fs_name_x       11

  defp clean_name(str) do
    [clean | _] = String.split(str, "\0")
    clean
  end

  def read_header(<<_length::8, @fs_volume::8, @magic::16-little, _checksum::16-little, rest::binary>>) do
    <<
      volume_number::16-little,
      current_date::32-little,
      dump_date::32-little,
      numwds::32-little,
      name_disk::binary-size(16),
      name_filesystem::binary-size(16),
      name_user::binary-size(16),
      dump_level::16-little,
      _::16, # padding
      rest_after::binary
    >> = rest
    struct = %{
      volume_number: volume_number,
      current_date: DateTime.from_unix!(current_date),
      dump_date: DateTime.from_unix!(dump_date),
      name_disk: clean_name(name_disk),
      name_filesystem: clean_name(name_filesystem),
      name_user: clean_name(name_user),
      dump_level: dump_level,
      numwds: numwds
    }
    {%{type: :volume, magic: @magic, contents: struct}, rest_after}
  end

  def read_header(<<length::8, @fs_name_x::8, @magic::16-little, _checksum::16-little, rest::binary>>) do
    name_length = (length * 8) - 64 # length of the binary below us up to the name
    <<
      num_links::16-little,
      inode::32-little,
      mode::32-little,
      uid::32-little,
      gid::32-little,
      size::32-little,
      atime::32-little,
      mtime::32-little,
      ctime::32-little,
      devmaj::32-little,
      devmin::32-little,
      rdevmaj::32-little,
      rdevmin::32-little,
      dsize::32-little,
      _::32,
      # name is rounded to quadwords
      name::binary-size(name_length),
      rest_after_name::binary
    >> = rest
    # we have to special-case link handling, ACLs aren't on symlinks
    {itype, _, _, _, _, _} = BFF.Mode.aix_mode(mode)
    {contents, rest_after_padding} = if itype == :link do
      <<
      contents_inner::binary-size(size), 
      rest_after_padding_inner::binary
      >> = rest_after_name
      {contents_inner, rest_after_padding_inner}
    else
      <<
      # read the sac_rec (two 32-bit lengths, representing how many 64-bit words in ACL)
      aclsize::32-little,
      pclsize::32-little,
      # someday we might interpret these AIX ACLs. they prob match the system headers
      _acls::binary-size(aclsize * 8),
      _pcls::binary-size(pclsize * 8),
      # we will eat the padding from quadword rounding later
      # because we can't put a case clause in the pattern (to handle 0, etc.)
      contents_inner::binary-size(size), 
      rest_after_padding_inner::binary
      >> = rest_after_name
      {contents_inner, rest_after_padding_inner}
    end
    # so handle it here
    content_padding_size = if size > 0 and rem(size, 8) != 0 do 8 - rem(size, 8) else 0 end
    <<_::binary-size(content_padding_size), rest_after::binary>> = rest_after_padding
    struct = %{
      num_links: num_links,
      inode: inode,
      mode: mode,
      uid: uid,
      gid: gid,
      size: size,
      atime: DateTime.from_unix!(atime),
      mtime: DateTime.from_unix!(mtime),
      ctime: DateTime.from_unix!(ctime),
      devmaj: devmaj,
      devmin: devmin,
      rdevmaj: rdevmaj,
      rdevmin: rdevmin,
      dsize: dsize,
      # note that this may have some stuff after the first null byte
      # looks like uninitialized data...
      name: clean_name(name),
      contents: contents
    }
    {%{length: length, type: :name_x, magic: @magic, contents: struct}, rest_after}
  end

  # XXX: How much can be made common with the non-packed version?
  def read_header(<<length::8, @fs_name_x::8, @packed_magic::16-little, _checksum::16-little, rest::binary>>) do
    name_length = (length * 8) - 64 # length of the binary below us up to the name
    <<
      num_links::16-little,
      inode::32-little,
      mode::32-little,
      uid::32-little,
      gid::32-little,
      size::32-little,
      atime::32-little,
      mtime::32-little,
      ctime::32-little,
      devmaj::32-little,
      devmin::32-little,
      rdevmaj::32-little,
      rdevmin::32-little,
      dsize::32-little,
      _::32,
      name::binary-size(name_length),
      aclsize::32-little,
      pclsize::32-little,
      _acls::binary-size(aclsize * 8),
      _pcls::binary-size(pclsize * 8),
      # dsize is the packed size, size is after unpacking
      packed_contents::binary-size(dsize), 
      rest_after_padding::binary
    >> = rest
    content_padding_size = if dsize > 0 and rem(dsize, 8) != 0 do 8 - rem(dsize, 8) else 0 end
    <<_::binary-size(content_padding_size), rest_after::binary>> = rest_after_padding
    # XXX: Extract the stuff inside (it's huffman encoded)
    struct = %{
      num_links: num_links,
      inode: inode,
      mode: mode,
      uid: uid,
      gid: gid,
      size: size,
      atime: DateTime.from_unix!(atime),
      mtime: DateTime.from_unix!(mtime),
      ctime: DateTime.from_unix!(ctime),
      devmaj: devmaj,
      devmin: devmin,
      rdevmaj: rdevmaj,
      rdevmin: rdevmin,
      dsize: dsize,
      name: clean_name(name),
      packed_contents: packed_contents
    }
    {%{length: length, type: :name_x, magic: @packed_magic, contents: struct}, rest_after}
  end

  def read_header(<<_length::8, @fs_end::8, @magic::16-little, _checksum::16-little, rest::binary>>) do
    # the stuff at the end looks to be uninitialized data. ugly!
    {:end, rest}
  end

  # Read a header without anytihng special (for unknown values)
  def read_header(<<length::8, type::8, @magic::16-little, checksum::16-little, rest::binary>>) do
    IO.inspect(length * 8, label: "Length (dwords) for unknown type")
    # per AIX, "the addressing unit is 8-byte "words", also known as dwords"
    # the header length includes itself, so - 6 bytes
    length_dwords = (length * 8) - 6
    <<contents::binary-size(length_dwords), rest_after::binary>> = rest
    {%{length: length, type: type, magic: @magic, checksum: checksum, contents: contents}, rest_after}
  end

  # artificial end
  defp munch_file(rest, [:end | _] = headers) do
    {headers |> Enum.reverse, rest}
  end

  defp munch_file(<<>>, headers) do
    headers |> Enum.reverse
  end

  defp munch_file(file, headers) do
    {header, rest} = read_header(file)
    munch_file(rest, [header | headers])
  end

  def read_file(file) do
    munch_file(file, [])
  end
end
