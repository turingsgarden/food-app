# DietAI24 Reproduction (ASA24 and Nutrition5k)

Reproduction of Yan et al. 2025, *DietAI24* (Communications Medicine 5:458): estimating energy, fat, carbohydrate, protein and food weight from food images with a multimodal LLM + retrieval over the FNDDS database.

- Model: `gpt-4o-2024-11-20` (the paper used GPT-4 Turbo)
- Embedding / vector database: OpenAI `text-embedding-3-large` + Chroma, built from FNDDS 2019-2020
- Prompts: taken verbatim from the paper's supplement where published
- Full record of what was done, what differs from the paper and the authors' code, and problems found: see the work log (to be added to this folder)

Author: Chengyuan Peng

## Pipeline

image -> GPT Vision description -> rewrite into several queries -> embeddings -> Chroma retrieval (top-4 per query, union) -> GPT Vision selects FNDDS food codes -> select FNDDS portion option and quantity -> grams -> nutrients (per-100 g value x grams / 100, summed over foods)

## Results (single run, MAE per image / per dish)

| Dataset | Source | Energy (kcal) | Fat (g) | Carbs (g) | Protein (g) | Weight (g) |
| --- | --- | --- | --- | --- | --- | --- |
| ASA24 | This repo (n=1355) | 132.4 | 6.76 | 15.54 | 7.28 | 84.2 |
| ASA24 | Paper (n=3000) | 47.7 | 1.8 | 6.95 | 1.38 | 49.4 |
| Nutrition5k | This repo (n=969) | 224.6 | 13.43 | 21.61 | 15.77 | 148.5 |
| Nutrition5k | Paper (n=1000) | 68.2 | 4.01 | 5.98 | 3.88 | 45.1 |

MAE is clearly worse than the paper. Standard deviations, success rates and the list of observed problems are in the work log. The ASA24 sample is smaller than the paper's (1,496 images selected, 1,355 used for MAE).

## Setup

1. Python virtual environment with the packages imported by the scripts (openai, chromadb, pandas, numpy, pillow; langchain packages only for `50_author_code_asa24.py`).
2. Create a `.env` file in the working directory containing `OPENAI_API_KEY=...`. Never commit this file.
3. Obtain the datasets yourself (not included here): FNDDS 2019-2020, NHANES dietary records, ASA24 portion images, Nutrition5k. Check the path constants at the top of each script and adjust them to your machine.

## Scripts (`src/`)

Final scripts used for the reported results:

| Script | Purpose |
| --- | --- |
| `01_build_fndds_kb.py` | Build the FNDDS knowledge-base tables |
| `19_build_chroma.py` | Build the Chroma vector database (text-embedding-3-large) |
| `05_top1000_intersect.py`, `06_relax_filters.py`, `07_sample_asa24.py` | ASA24 sample selection (NHANES top-1000 food codes intersected with FNDDS and available images) |
| `18_sample_n5k.py` | Nutrition5k sample selection (deduplicated, seed 42) |
| `30_run_asa24.py` | ASA24 pipeline (final ASA24 result) |
| `31_paper_table.py`, `32_code_accuracy.py`, `33_export_csv.py` | ASA24 MAE table, Exact/Close/Far/Mismatch, CSV export |
| `44_n5k_paper_flow.py` | Nutrition5k paper-flow pipeline (final Nutrition5k result) |
| `46_mae_sd.py`, `47_mae_sd_final.py` | MAE +/- 1 SD compared with the paper |

Earlier versions, helpers and checks (not used for the final numbers):

| Script | Purpose |
| --- | --- |
| `40_run_nutrition5k.py`, `41_fill_weights.py`, `42_export_n5k_csv.py`, `43_n5k_portion.py` | Nutrition5k v2/v3 versions; `40` and `43` also hold helper functions and prompts imported by `44` |
| `50_author_code_asa24.py` | The authors' public retrieval code adapted to the OpenAI API, trial on about 35 ASA24 images |
| `00`-`04`, `08`-`17`, `20`-`23` | Data inspection, ground-truth construction and checks, early pilot pipeline, vector-database visualization |

## Suggested run order

1. `01_build_fndds_kb.py` then `19_build_chroma.py`
2. Sampling: `05`, `06`, `07` (ASA24) and `18` (Nutrition5k)
3. ASA24: `30` then `31`, `32`, `33`
4. Nutrition5k: `40` (the description step is reused by `44`), then `44`
5. MAE +/- SD: `47_mae_sd_final.py`

Each script prints its progress; run them from the project root.

## Notes

- Not included: API keys, datasets, the Chroma database and per-image JSON outputs.
- The authors' code is at https://github.com/Runz96/DietAI. It uses Azure OpenAI and its mixed-dish (Nutrition5k) prompts are not public, so the complete authors' pipeline could not be run as is.