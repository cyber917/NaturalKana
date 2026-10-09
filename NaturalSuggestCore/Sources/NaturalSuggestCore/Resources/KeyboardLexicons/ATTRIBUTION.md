# Offline keyboard vocabulary

fr.txt, ru.txt and ko.txt are derived from wordfreq 3.1.1 by Robyn Speer:
https://github.com/rspeer/wordfreq
https://pypi.org/project/wordfreq/3.1.1/

The word-list data and these derived lists are distributed under Creative Commons
Attribution-ShareAlike 4.0: https://creativecommons.org/licenses/by-sa/4.0/
This data license applies to the word lists, not NaturalKana's source code.

Modifications: select the first 15,000 words of length 1–32 after filtering each
language to its writing system; remove numeric/punctuation-only tokens; preserve
source frequency order. No runtime dependency on wordfreq is needed.
Regenerate with tools/export_keyboard_lexicons.py and wordfreq==3.1.1.
Frequency data is not a normative dictionary; native-speaker review is welcome.

zh-pinyin.txt is the Chinese pinyin dictionary. Its words and their order come from
the same wordfreq 3.1.1 data (CC BY-SA 4.0); the pinyin readings were generated with
pypinyin 0.55.0 by mozillazg (MIT, see pypinyin-LICENSE.txt), whose phrase and
character readings come from the MIT-licensed phrase-pinyin-data and pinyin-data.
Modifications: keep the first 80,000 words written only in Han characters, add about
60 everyday chat words, write each reading as toneless syllables with ü as v, add the
other readings of single characters at the end, and read 嗯 as en. The derived list is
distributed under CC BY-SA 4.0. Regenerate with tools/export_pinyin_lexicon.py.

zh-chat-pinyin.txt supplements the Chinese input dictionary with colloquial phrases.
Source: CC-CEDICT, published by MDBG and maintained by its contributors:
https://www.mdbg.net/chinese/dictionary?page=cedict
https://cc-cedict.org/wiki/
Original CEDICT: Copyright (C) 1997, 1998 Paul Andrew Denisowski.
License: Creative Commons Attribution-ShareAlike 4.0 International:
https://creativecommons.org/licenses/by-sa/4.0/

Snapshot: 2026-10-09T09:12:50Z. Source URL and SHA-256 hashes are recorded in
tools/data/cedict-snapshot.json. The reviewed source excerpt, including its original
notices, is preserved in tools/data/cc-cedict-chat.txt. This is a selection and
adaptation, not the complete dictionary, and is not endorsed by MDBG.
Modifications: select colloquial, slang, Internet, neologism and dialect labels;
keep 2–12 Han characters with one syllable per character; use simplified spelling,
remove tone numbers and map ü to v. Omit definitions from the runtime word list.
Add separately maintained conversational phrases from tools/data/pinyin-chat.tsv.
Both the excerpt and the resulting supplement remain CC BY-SA 4.0; the original
NaturalKana phrase additions are contributed under that same license.
The third column gives a ranking prior, not a measured corpus frequency; existing
more-frequent entries and personal learning can still rank ahead of it.
Regenerate offline with `python3 tools/export_pinyin_chat.py`; no downloads, account,
training or network requests occur on the user's device.

Upstream licensing, attribution and source citations follow.

## License

`wordfreq` is freely redistributable under the Apache license (see
`LICENSE.txt`), and it includes data files that may be
redistributed under a Creative Commons Attribution-ShareAlike 4.0
license (<https://creativecommons.org/licenses/by-sa/4.0/>).

`wordfreq` contains data extracted from Google Books Ngrams
(<http://books.google.com/ngrams>) and Google Books Syntactic Ngrams
(<http://commondatastorage.googleapis.com/books/syntactic-ngrams/index.html>).
The terms of use of this data are:

    Ngram Viewer graphs and data may be freely used for any purpose, although
    acknowledgement of Google Books Ngram Viewer as the source, and inclusion
    of a link to http://books.google.com/ngrams, would be appreciated.

`wordfreq` also contains data derived from the following Creative Commons-licensed
sources:

- The Leeds Internet Corpus, from the University of Leeds Centre for Translation
  Studies (<http://corpus.leeds.ac.uk/list.html>)

- Wikipedia, the free encyclopedia (<http://www.wikipedia.org>)

- ParaCrawl, a multilingual Web crawl (<https://paracrawl.eu>)

It contains data from OPUS OpenSubtitles 2018
(<http://opus.nlpl.eu/OpenSubtitles.php>), whose data originates from the
OpenSubtitles project (<http://www.opensubtitles.org/>) and may be used with
attribution to OpenSubtitles.

It contains data from various SUBTLEX word lists: SUBTLEX-US, SUBTLEX-UK,
SUBTLEX-CH, SUBTLEX-DE, and SUBTLEX-NL, created by Marc Brysbaert et al.
(see citations below) and available at
<http://crr.ugent.be/programs-data/subtitle-frequencies>.

I (Robyn Speer) have obtained permission by e-mail from Marc Brysbaert to
distribute these wordlists in wordfreq, to be used for any purpose, not just
for academic use, under these conditions:

- Wordfreq and code derived from it must credit the SUBTLEX authors.
- It must remain clear that SUBTLEX is freely available data.

These terms are similar to the Creative Commons Attribution-ShareAlike license.

Some additional data was collected by a custom application that watches the
streaming Twitter API, in accordance with Twitter's Developer Agreement &
Policy. This software gives statistics about words that are commonly used on
Twitter; it does not display or republish any Twitter content.

## Citing wordfreq

If you use wordfreq in your research, please cite it! We publish the code
through Zenodo so that it can be reliably cited using a DOI. The current
citation is:

> Robyn Speer. (2022). rspeer/wordfreq: v3.0 (v3.0.2). Zenodo. https://doi.org/10.5281/zenodo.7199437

The same citation in BibTex format:

```
@software{robyn_speer_2022_7199437,
  author       = {Robyn Speer},
  title        = {rspeer/wordfreq: v3.0},
  month        = sep,
  year         = 2022,
  publisher    = {Zenodo},
  version      = {v3.0.2},
  doi          = {10.5281/zenodo.7199437},
  url          = {https://doi.org/10.5281/zenodo.7199437}
}
```

## Citations to work that wordfreq is built on

- Bojar, O., Chatterjee, R., Federmann, C., Haddow, B., Huck, M., Hokamp, C.,
  Koehn, P., Logacheva, V., Monz, C., Negri, M., Post, M., Scarton, C.,
  Specia, L., & Turchi, M. (2015). Findings of the 2015 Workshop on Statistical
  Machine Translation.
  <http://www.statmt.org/wmt15/results.html>

- Brysbaert, M. & New, B. (2009). Moving beyond Kucera and Francis: A Critical
  Evaluation of Current Word Frequency Norms and the Introduction of a New and
  Improved Word Frequency Measure for American English. Behavior Research
  Methods, 41 (4), 977-990.
  <http://sites.google.com/site/borisnew/pub/BrysbaertNew2009.pdf>

- Brysbaert, M., Buchmeier, M., Conrad, M., Jacobs, A.M., Bölte, J., & Böhl, A.
  (2011). The word frequency effect: A review of recent developments and
  implications for the choice of frequency estimates in German. Experimental
  Psychology, 58, 412-424.

- Cai, Q., & Brysbaert, M. (2010). SUBTLEX-CH: Chinese word and character
  frequencies based on film subtitles. PLoS One, 5(6), e10729.
  <http://journals.plos.org/plosone/article?id=10.1371/journal.pone.0010729>

- Davis, M. (2012). Unicode text segmentation. Unicode Standard Annex, 29.
  <http://unicode.org/reports/tr29/>

- Halácsy, P., Kornai, A., Németh, L., Rung, A., Szakadát, I., & Trón, V.
  (2004). Creating open language resources for Hungarian. In Proceedings of the
  4th international conference on Language Resources and Evaluation (LREC2004).
  <http://mokk.bme.hu/resources/webcorpus/>

- Keuleers, E., Brysbaert, M. & New, B. (2010). SUBTLEX-NL: A new frequency
  measure for Dutch words based on film subtitles. Behavior Research Methods,
  42(3), 643-650.
  <http://crr.ugent.be/papers/SUBTLEX-NL_BRM.pdf>

- Kudo, T. (2005). Mecab: Yet another part-of-speech and morphological
  analyzer.
  <http://mecab.sourceforge.net/>

- Lin, Y., Michel, J.-B., Aiden, E. L., Orwant, J., Brockman, W., and Petrov,
  S. (2012). Syntactic annotations for the Google Books Ngram Corpus.
  Proceedings of the ACL 2012 system demonstrations, 169-174.
  <http://aclweb.org/anthology/P12-3029>

- Lison, P. and Tiedemann, J. (2016). OpenSubtitles2016: Extracting Large
  Parallel Corpora from Movie and TV Subtitles. In Proceedings of the 10th
  International Conference on Language Resources and Evaluation (LREC 2016).
  <http://stp.lingfil.uu.se/~joerg/paper/opensubs2016.pdf>

- Ortiz Suárez, P. J., Sagot, B., and Romary, L. (2019). Asynchronous pipelines
  for processing huge corpora on medium to low resource infrastructures. In
  Proceedings of the Workshop on Challenges in the Management of Large Corpora
  (CMLC-7) 2019.
  <https://oscar-corpus.com/publication/2019/clmc7/asynchronous/>

- ParaCrawl (2018). Provision of Web-Scale Parallel Corpora for Official
  European Languages. <https://paracrawl.eu/>

- van Heuven, W. J., Mandera, P., Keuleers, E., & Brysbaert, M. (2014).
  SUBTLEX-UK: A new and improved word frequency database for British English.
  The Quarterly Journal of Experimental Psychology, 67(6), 1176-1190.
  <http://www.tandfonline.com/doi/pdf/10.1080/17470218.2013.850521>


NaturalKana additionally prepends common Korean polite forms (see the reproducible exporter); the resulting Korean list is also distributed under CC BY-SA 4.0. These supplemental forms need native-speaker review.

## Multilingual conversation supplements

`en-chat.tsv`, `ja-chat.tsv`, `fr-chat.tsv`, `ru-chat.tsv`, and `ko-chat.tsv`
contain 531 short conversational entries maintained in this repository. They
are original NaturalKana additions under the root MIT license, independent of
the wordfreq-derived lists above. Entries include informal language and slang;
native-speaker review is still needed. File order is editorial, not a measured
frequency ranking. No chat histories or personal messages were used as a corpus.
