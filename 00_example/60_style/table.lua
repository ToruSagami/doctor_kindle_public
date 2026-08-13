-- PDF用の表配置と罫線制御
--
-- 表の直前で本文領域の70パーセントを要求し、
-- 空きが不足していれば表を次ページへ送る。
--
-- 3列以上の表は、視線が行をまたいで迷わないよう、
-- 各データ行の下へ薄い横罫線を自動で付ける。
-- 1〜2列の表は従来どおりの簡潔な体裁を維持する。
-- 縦罫線は付けない。

local function column_count(tbl)
  if tbl.colspecs then
    return #tbl.colspecs
  end

  return 0
end

local function add_body_row_rules(latex)
  local body_start = latex:find("\\endlastfoot", 1, true)
  local table_end = latex:find("\\end{longtable}", 1, true)

  if not body_start or not table_end or body_start >= table_end then
    return latex
  end

  body_start = body_start + #"\\endlastfoot"
  local before = latex:sub(1, body_start)
  local body = latex:sub(body_start + 1, table_end - 1)
  local after = latex:sub(table_end)

  -- Pandocのlongtable本文では、各データ行は \\ で終わる。
  -- 行間だけに薄い罫線を入れ、最終行の後には追加しない。
  local row_break = " \\\\\n"
  local matches = {}
  local search_from = 1

  while true do
    local s, e = body:find(row_break, search_from, true)
    if not s then
      break
    end

    matches[#matches + 1] = { start_pos = s, end_pos = e }
    search_from = e + 1
  end

  if #matches <= 1 then
    return latex
  end

  local pieces = {}
  local cursor = 1

  for index, match in ipairs(matches) do
    pieces[#pieces + 1] = body:sub(cursor, match.end_pos)

    -- 最後のデータ行はlongtable自身の終端罫線に任せる。
    if index < #matches then
      pieces[#pieces + 1] =
        "\\noalign{\\color{booktablerule}\\hrule height 0.25pt}\n"
    end

    cursor = match.end_pos + 1
  end

  pieces[#pieces + 1] = body:sub(cursor)

  return before .. table.concat(pieces) .. after
end

function Table(tbl)
  if not FORMAT:match("latex") then
    return tbl
  end

  local blocks = {
    pandoc.RawBlock("latex", "\\Needspace{0.70\\textheight}")
  }

  if column_count(tbl) < 3 then
    blocks[#blocks + 1] = tbl
    return blocks
  end

  -- 3列以上だけLaTeXへ一度書き出して、本文行間へ薄い罫線を追加する。
  local latex = pandoc.write(
    pandoc.Pandoc({ tbl }),
    "latex"
  )

  latex = add_body_row_rules(latex)
  blocks[#blocks + 1] = pandoc.RawBlock("latex", latex)

  return blocks
end
