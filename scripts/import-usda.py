"""Rebuild the bundled per-100-g catalog from the official USDA SR Legacy CSV archive.
Usage: python3 scripts/import-usda.py path/to/FoodData_Central_sr_legacy_food_csv_2018-04.zip
No API key or runtime network access is required. Missing nutrients are never replaced with zero.
"""
import csv, io, json, sys, zipfile
from pathlib import Path
z = zipfile.ZipFile(sys.argv[1])
def rows(name):
    path = next(n for n in z.namelist() if n.endswith('/'+name))
    return csv.DictReader(io.TextIOWrapper(z.open(path), encoding='utf-8-sig'))
nutrients = {}
keys = {'1008':'calories', '1003':'protein', '1004':'fat', '1005':'carbs'}
for row in rows('food_nutrient.csv'):
    if row['nutrient_id'] in keys and row['amount']:
        nutrients.setdefault(row['fdc_id'], {})[keys[row['nutrient_id']]] = float(row['amount'])
foods=[]
for row in rows('food.csv'):
    n=nutrients.get(row['fdc_id'], {})
    if len(n)!=4 or any(v<0 for v in n.values()) or n['calories']>1000 or sum(n[k] for k in ['protein','fat','carbs'])>100.5:
        continue
    foods.append({'id':int(row['fdc_id']), 'name':row['description'], 'per100':n})
foods.sort(key=lambda f:f['id'])
out=Path('Sources/NutritionCore/Resources'); out.mkdir(exist_ok=True)
(out/'usda-sr-legacy.json').write_text(json.dumps(foods, ensure_ascii=False, separators=(',',':'))+'\n')
print(f'{len(foods)} complete records; {len(list(rows("food.csv")))-len(foods)} excluded (missing or invalid macro data)')
