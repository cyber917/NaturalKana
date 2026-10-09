import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("export_pinyin_chat", Path(__file__).resolve().parents[1] / "export_pinyin_chat.py")
chat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chat)


class ChatExportTests(unittest.TestCase):
    def test_selects_labels_and_simplified_readings(self):
        source = "\n".join([
            "擺爛 摆烂 [bai3 lan4] /(neologism) (slang) to stop striving/",
            "無語 无语 [wu2 yu3] /(coll.) speechless/",
            "呂布 吕布 [Lu:3 Bu4] /(Internet slang) example/",
            "字典 字典 [zi4 dian3] /dictionary/",
            "A咖 A咖 [A ka1] /(coll.) A-list/",
            "玩意兒 玩意儿 [wan2 yi4 r5] /(coll.) thing/",
        ])
        self.assertEqual(chat.extract(source), [("吕布", "lv bu"), ("摆烂", "bai lan"), ("无语", "wu yu"), ("玩意儿", "wan yi r")])

    def test_bad_or_unaligned_readings_are_not_imported(self):
        source = "\n".join([
            "網絡 网络 [wang3 luo4] /network/",
            "胡說 胡说 [hu2] /(slang) incomplete reading/",
            "亂來 乱来 [luan4 123] /(slang) invalid reading/",
            "not a dictionary entry",
        ])
        self.assertEqual(chat.extract(source), [])

    def test_deduplicates_but_preserves_alternate_readings(self):
        source = "\n".join([
            "誰呀 谁呀 [shei2 ya5] /(coll.) who?/",
            "誰呀 谁呀 [shui2 ya5] /(coll.) who?/",
            "誰呀 谁呀 [shei2 ya5] /(coll.) who?/",
        ])
        self.assertEqual(chat.extract(source), [("谁呀", "shei ya"), ("谁呀", "shui ya")])

    def test_curated_phrases_require_one_reading_per_character(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "phrases.tsv"
            path.write_text("是啥\tshi sha\n是啥\tshi sha\n", encoding="utf-8")
            self.assertEqual(chat.curated(path), [("是啥", "shi sha")])
            path.write_text("是啥\tshi\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                chat.curated(path)


if __name__ == "__main__":
    unittest.main()
