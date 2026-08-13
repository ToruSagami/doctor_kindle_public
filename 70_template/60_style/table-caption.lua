-- 表キャプションの連番
--
-- Markdownでは、表の直後に次の形式でキャプションを書く。
--
-- : 出力形式の違い
--
-- 原稿には「表1」などの番号を書かない。
-- PDFではLaTeX側のtableカウンタに任せ、
-- EPUB/DOCXではこのフィルターが「表1」「表2」...を付ける。

local table_number = 0

local function has_caption(tbl)
  return tbl.caption
    and tbl.caption.long
    and #tbl.caption.long > 0
end

local function prefix_caption(tbl, number)
  local first = tbl.caption.long[1]

  if first and (first.t == "Plain" or first.t == "Para") then
    first.content:insert(1, pandoc.Space())
    first.content:insert(1, pandoc.Str("表" .. number))
  end
end

function Table(tbl)
  if not has_caption(tbl) then
    return tbl
  end

  table_number = table_number + 1

  -- PDFはpdf-header.texで「表1」の形式に自動採番する。
  if not FORMAT:match("latex") then
    prefix_caption(tbl, table_number)
  end

  return tbl
end
