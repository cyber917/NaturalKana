"""Regenerate the offline pinyin dictionary with wordfreq==3.1.1 and pypinyin==0.55.0."""
from importlib.metadata import version
from pathlib import Path
from pypinyin import Style, lazy_pinyin, pinyin
from wordfreq import top_n_list

assert version("wordfreq") == "3.1.1" and version("pypinyin") == "0.55.0"
output = Path(__file__).resolve().parents[1] / "NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/KeyboardLexicons/zh-pinyin.txt"

def hanzi(word):
    return 1 <= len(word) <= 12 and all(0x4E00 <= ord(c) <= 0x9FFF for c in word)

def syllables(word):
    result = lazy_pinyin(word, style=Style.NORMAL, v_to_u=False, errors="ignore")
    return result if len(result) == len(word) and all(s.isascii() and s.isalpha() for s in result) else None

words = [word for word in top_n_list("zh", 100000) if hanzi(word)][:80000]
# Everyday chat words that are not single tokens in the frequency data; they rank among common words.
chat = "好的 嗯嗯 我想 你们好 在吗 晚安 早安 早上好 辛苦了 谢谢你 不客气 没问题 好吧 怎么了 干嘛 知道了 好久不见 是的 不是 可以吗 什么时候 怎么样 哈哈哈 拜拜 加油 收到 稍等 马上 等一下 对不起 没关系 一起 吃饭 下班 上班 明天见 你好吗 吃饭了吗 在干嘛 怎么办 为什么 我也是 我知道 太好了 真的吗 好不好 对吧 是吗 我觉得 我们 一下 有空 回家 睡觉 起床 想你 爱你".split()
words = list(dict.fromkeys(words[:1500] + chat + words[1500:]))
# Readings pypinyin gives in a form nobody types.
override = {"嗯": ["en"], "嗯嗯": ["en", "en"], "呣": ["m"]}
lines, alternates = [], []
for word in words:
    reading = override.get(word) or syllables(word)
    if not reading:
        continue
    lines.append(f"{word}\t{' '.join(reading)}")
    if len(word) == 1 and word not in override:
        # Other readings of a single character (了 liao, 行 hang) follow every primary entry.
        for other in pinyin(word, style=Style.NORMAL, heteronym=True, v_to_u=False)[0][1:]:
            if other.isascii() and other.isalpha() and other != reading[0]:
                alternates.append(f"{word}\t{other}")
entries = lines + list(dict.fromkeys(alternates))
header = ("# Source: wordfreq 3.1.1 (Robyn Speer, data CC BY-SA 4.0) and pypinyin 0.55.0 (MIT).\n"
          "# Derived: first 80,000 Han-only words in frequency order with their pinyin, plus common chat words\n"
          "# and alternative readings of single characters. One entry per line: word, tab, syllables. See ATTRIBUTION.md.\n")
output.write_text(header + "\n".join(entries) + "\n", encoding="utf-8")
print(len(lines), len(alternates), output.stat().st_size)
