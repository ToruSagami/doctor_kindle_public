-- 見出し番号の階層を全出力形式で統一する。
--
-- レベル1の見出しを章、レベル2を節として番号付けする。
-- レベル3以降は小見出しとして番号を付けない。
-- 「はじめに」と、その中のレベル2見出しは番号なしとする。
-- 「おわりに」自身と、それ以降のすべての見出しを番号なしとする。

local in_intro = false
local after_outro = false

local function has_class(element, class_name)
  for _, class in ipairs(element.classes) do
    if class == class_name then
      return true
    end
  end

  return false
end

local function add_class(element, class_name)
  if not has_class(element, class_name) then
    element.classes:insert(class_name)
  end
end

function Header(header)
  local title = pandoc.utils.stringify(header.content)

  if header.level == 1 then
    if title == "はじめに" then
      in_intro = true
      add_class(header, "unnumbered")
    elseif in_intro then
      in_intro = false
    end
  end

  if in_intro and header.level == 2 then
    add_class(header, "unnumbered")
  end

  if header.level == 1 and title == "おわりに" then
    after_outro = true
  end

  if after_outro or header.level >= 3 then
    add_class(header, "unnumbered")
  end

  return header
end
