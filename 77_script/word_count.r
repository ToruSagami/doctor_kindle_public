# 必要パッケージ
#require("RmeCab")
#install.packages("RMeCab", repos = "http://rmecab.jp/R")
library(RMeCab)
library(dplyr)
library(stringr)
library(tibble)
library(readr)
library(here)
library(purrr)

# =========================
# 1. 原稿ファイルを指定
# =========================

file_path <- "./10_manuscript/99_master.md"  # 自分のMarkdownファイル名に変更

text <- readLines(file_path, encoding = "UTF-8", warn = FALSE)

# =========================
# 2. Markdown記号などを軽く掃除
# =========================

text_clean <- text %>%
  str_replace_all("^#+\\s*", "") %>%       # 見出し記号
  str_replace_all("\\*\\*", "") %>%        # 太字
  str_replace_all("\\*", "") %>%           # 箇条書きや斜体
  str_replace_all("!\\[.*?\\]\\(.*?\\)", "") %>% # 画像
  str_replace_all("\\[.*?\\]\\(.*?\\)", "") %>%  # リンク
  str_replace_all("[「」『』（）()【】［］]", "") %>%
  str_replace_all("[、。！？!?：:；;]", " ") %>%
  str_trim()

# 空行を除外
text_clean <- text_clean[text_clean != ""]

# 一時ファイルに保存
tmp_file <- tempfile(fileext = ".txt")
writeLines(text_clean, tmp_file, useBytes = TRUE)

# =========================
# 3. RMeCabで形態素解析
# =========================

res <- RMeCabText(tmp_file)

# RMeCabTextの結果をデータフレーム化
tokens <- tibble(
  word = map_chr(res, 1),
  pos = map_chr(res, 2)
)
tokens <- tibble(
  word = map_chr(res, 1),
  pos1 = map_chr(res, 2),
  pos2 = map_chr(res, 3),
  pos3 = map_chr(res, 4)
)
# =========================
# 4. 品詞を絞って集計
# =========================

target_pos <- c("名詞", "動詞", "形容詞", "副詞","接続詞")

freq <- tokens %>%
  filter(str_detect(pos1, paste(target_pos, collapse = "|"))) %>%
  filter(!str_detect(word, "^[0-9０-９]+$")) %>%  # 数字だけを除外
  filter(nchar(word) >= 2) %>%                    # 1文字語を除外
  count(word, sort = TRUE)

# =========================
# 5. 上位表示
# =========================

View(freq)
print(head(freq, 1000))

# CSVに保存
write_csv(freq, "98_work/word_frequency.csv")
