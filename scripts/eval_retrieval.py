import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORPUS_PATH = ROOT / "data" / "educational_corpus.seed.json"

TEST_QUERIES = [
    ("a1c", "what does high a1c mean"),
    ("lipids", "why is ldl cholesterol important"),
    ("cbc", "what does low hemoglobin mean"),
    ("cmp", "why is creatinine high"),
]


def simple_score(text: str, query: str) -> int:
    tokens = [t for t in query.lower().split() if len(t) > 2]
    text_l = text.lower()
    return sum(1 for t in tokens if t in text_l)


def retrieve(corpus, panel: str, query: str, top_k: int = 3):
    candidates = [c for c in corpus if c["panel"] in (panel, "general")]
    ranked = sorted(
        candidates,
        key=lambda x: (simple_score(x["text"], query), 1 if x["panel"] == panel else 0),
        reverse=True,
    )
    return ranked[:top_k]


def main() -> int:
    corpus = json.loads(CORPUS_PATH.read_text(encoding="utf-8"))

    print("Retrieval relevance quick check")
    print("=" * 40)

    failures = 0
    for panel, query in TEST_QUERIES:
        hits = retrieve(corpus, panel, query, top_k=3)
        top = hits[0] if hits else None
        ok = bool(top) and top["panel"] in (panel, "general")
        if not ok:
            failures += 1

        print(f"Panel: {panel}")
        print(f"Query: {query}")
        if top:
            print(f"Top source: {top['source']}")
            print(f"Top topic : {top['topic']}")
            print(f"Top panel : {top['panel']}")
        else:
            print("Top result: none")
        print(f"Status: {'PASS' if ok else 'FAIL'}")
        print("-" * 40)

    if failures:
        print(f"Completed with {failures} failed query checks.")
        return 1

    print("All query checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
