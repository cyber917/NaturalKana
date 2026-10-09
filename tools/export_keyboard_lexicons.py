"""Regenerate offline keyboard word lists with wordfreq==3.1.1."""
from importlib.metadata import version
from pathlib import Path
import unicodedata
from wordfreq import top_n_list

assert version("wordfreq") == "3.1.1"
output = Path(__file__).resolve().parents[1] / "NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/KeyboardLexicons"
for language in ["fr", "ru", "ko"]:
    def valid(word):
        if not 1 <= len(word) <= 32 or not word[0].isalpha() or not word[-1].isalpha():
            return False
        if language == "ko":
            return all(0xAC00 <= ord(c) <= 0xD7A3 for c in word)
        if language == "ru":
            return all(0x400 <= ord(c) <= 0x4FF or c == "-" for c in word)
        return all((c.isalpha() and "LATIN" in unicodedata.name(c, "")) or c in "'-’" for c in word)

    words = [word for word in top_n_list(language, 60000) if valid(word)][:15000]
    if language == "ko":
        polite_forms = "안녕하세요 감사합니다 고마워요 고맙습니다 죄송합니다 미안해요 괜찮아요 좋아요 싫어요 맞아요 아니에요 네 아니요 있어요 없어요 알아요 몰라요 알겠습니다 모르겠어요 이해했어요 부탁합니다 부탁드려요 축하합니다 반갑습니다 반가워요 환영합니다 잘했어요 잘해요 예뻐요 멋있어요 맛있어요 맛없어요 배고파요 배불러요 피곤해요 졸려요 행복해요 슬퍼요 아파요 추워요 더워요 재미있어요 재미없어요 어려워요 쉬워요 필요해요 괜찮습니다 가능합니다 불가능합니다 좋아합니다 사랑해요 보고싶어요 먹어요 마셔요 가요 와요 봐요 해요 주세요 도와주세요 기다려주세요 말씀하세요 실례합니다 어서오세요 다녀왔어요 다녀오겠습니다 조심하세요 수고하세요 수고하셨습니다 잘자요 잘잤어요 만나요 내일 만났어요 먹었어요 마셨어요 갔어요 왔어요 봤어요 했어요 할게요 갈게요 올게요 먹을게요".split()
        words = list(dict.fromkeys(polite_forms + words))
    header = "# Source: wordfreq 3.1.1, Robyn Speer. Data: CC BY-SA 4.0.\n# Derived: first 15,000 script-filtered words in frequency order. Korean also includes common polite forms. See ATTRIBUTION.md.\n"
    (output / f"{language}.txt").write_text(header + "\n".join(words) + "\n", encoding="utf-8")
    print(language, len(words))
