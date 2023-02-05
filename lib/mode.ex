defmodule BFF.Mode do
  defp aix_mode_type(1), do: :fifo
  defp aix_mode_type(2), do: :char
  defp aix_mode_type(4), do: :dir
  defp aix_mode_type(6), do: :block
  defp aix_mode_type(8), do: :file
  defp aix_mode_type(10), do: :link
  defp aix_mode_type(12), do: :socket
  defp aix_mode_type(_), do: :unknown

  defp aix_mode_type_char(:dir), do: "d"
  defp aix_mode_type_char(:link), do: "l"
  defp aix_mode_type_char(:file), do: "-"
  #defp aix_mode_type_char(_), do: "-"

  defp aix_mode_perm_string(bits, inherit_id) do
    <<r::1, w::1, x::1>> = <<bits::3>>
    if r == 1 do "r" else "-" end
    <> if w == 1 do "w" else "-" end
    <> cond do
      x == 1 and inherit_id == 1 -> "s"
      x == 1 -> "x"
      true -> "-"
    end
  end

  def mode_string({itype, isuid, isgid, ipusr, ipgrp, ipoth}) do
    aix_mode_type_char(itype)
    <> aix_mode_perm_string(ipusr, isuid)
    <> aix_mode_perm_string(ipgrp, isgid)
    <> aix_mode_perm_string(ipoth, 0)
  end

  def aix_mode(mode) do
    <<
      itype::4,
      isuid::1,
      isgid::1,
      _isvtx::1, # "save text"
      ipusr::3,
      ipgrp::3,
      ipoth::3,
    >> = <<mode::16>>
    {aix_mode_type(itype), isuid, isgid, ipusr, ipgrp, ipoth}
  end
end
