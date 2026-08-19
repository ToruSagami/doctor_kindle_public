-- PDF用の表配置制御
--
-- 表の直前で本文領域の70パーセントを要求し、
-- 空きが不足していれば表を次ページへ送る。
--
-- 表の列幅、文字配置、罫線はPandocの標準処理へ任せる。
-- 列数や見出しの内容による個別処理は行わない。

function Table(tbl)
  if not FORMAT:match("latex") then
    return tbl
  end

  return {
    pandoc.RawBlock(
      "latex",
      "\\Needspace{0.70\\textheight}"
    ),
    tbl
  }
end
