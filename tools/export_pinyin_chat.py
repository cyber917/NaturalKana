"""Export an offline chat supplement from a CC-CEDICT snapshot and reviewed local phrases."""
import argparse
import gzip
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tools/data"
OUTPUT = ROOT / "NaturalSuggestCore/Sources/NaturalSuggestCore/Resources/KeyboardLexicons/zh-chat-pinyin.txt"
LABEL = re.compile(r"\([^)]*(?:coll\.|colloquial|slang|Internet|neologism|dialect)[^)]*\)", re.I)
ENTRY = re.compile(r"^\S+ (\S+) \[([^\]]+)\] /(.*)/$")


def valid(word, syllables):
    return (2 <= len(word) <= 12 and all(0x4E00 <= ord(c) <= 0x9FFF for c in word)
            and len(syllables) == len(word) and all(re.fullmatch(r"[a-z]+", s) for s in syllables))


def extract(text):
    entries = set()
    for line in text.splitlines():
        match = ENTRY.match(line)
        if not match:
            continue
        word, reading, meanings = match.groups()
        if not LABEL.search(meanings):
            continue
        syllables = [re.sub(r"[1-5]$", "", s.lower()).replace("u:", "v") for s in reading.split()]
        if valid(word, syllables):
            entries.add((word, " ".join(syllables)))
    return sorted(entries)


def curated(path):
    entries = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        word, reading = line.split("\t")
        if not valid(word, reading.split()):
            raise ValueError(f"Invalid phrase at line {number}")
        entries.append((word, reading))
    return list(dict.fromkeys(entries))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=DATA / "cc-cedict-chat.txt",
                        help="Reviewed text subset (default), or the original .txt.gz snapshot")
    args = parser.parse_args()
    metadata = json.loads((DATA / "cedict-snapshot.json").read_text())
    source = args.source.read_bytes()
    compressed = args.source.suffix == ".gz"
    expected = metadata["sha256" if compressed else "subsetSHA256"]
    if hashlib.sha256(source).hexdigest() != expected:
        raise SystemExit("Source differs from the reviewed snapshot; review the new data and update its metadata first.")
    entries = extract((gzip.decompress(source) if compressed else source).decode("utf-8"))
    phrases = curated(DATA / "pinyin-chat.tsv")
    explicit = set(phrases)
    lines = [f"{word}\t{reading}\t1500" for word, reading in phrases]
    lines += [f"{word}\t{reading}\t5000" for word, reading in entries if (word, reading) not in explicit]
    header = ("# CC-CEDICT (MDBG and contributors), CC BY-SA 4.0; see ATTRIBUTION.md.\n"
              f"# Snapshot {metadata['date']}; extracted colloquial, slang, Internet, neologism and dialect labels.\n"
              "# Includes separately maintained NaturalKana chat phrases, also CC BY-SA 4.0.\n"
              "# word<TAB>toneless pinyin<TAB>ranking prior (not measured frequency).\n")
    OUTPUT.write_text(header + "\n".join(lines) + "\n", encoding="utf-8")
    print(f"{len(phrases)} maintained phrases; {len(entries)} source entries; {len(lines)} distinct readings; {OUTPUT.stat().st_size} bytes")


if __name__ == "__main__":
    main()
