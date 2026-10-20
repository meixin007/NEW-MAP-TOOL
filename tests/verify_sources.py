"""Standard-library source/sample integrity check; never rewrites user content."""
from pathlib import Path
import argparse,hashlib,json,struct
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);a=p.parse_args()
base=json.loads((root/'docs/review_c7e0/BASE_MANIFEST.json').read_text(encoding='utf-8'))
failures=[];preserved=[];sample_rows=[]
exceptions=json.loads((root/'docs/review_pr1/BASELINE_EXCEPTIONS.json').read_text(encoding='utf-8'))['files'] if (root/'docs/review_pr1/BASELINE_EXCEPTIONS.json').exists() else {}
explicit_changes=[]
for item in base['files']:
    name=item['path']
    if name.startswith('samples/') or (name.startswith('addons/') and '/workshop_s1/' not in name):
        if name in exceptions:
            entry=exceptions[name];file=root/name
            ok=entry['base_sha256']==item['base_sha256'] and file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest()==entry['current_sha256'] and bool(entry['reason'])
            if not ok:failures.append('Explicit change hash mismatch: '+name)
            explicit_changes.append(dict(path=name,passed=ok,**entry));continue
        file=root/name;ok=file.is_file() and hashlib.sha256(file.read_bytes()).hexdigest()==item['base_sha256']
        if not ok:failures.append('Baseline content changed: '+name)
        preserved.append(dict(path=name,passed=ok))
referenced=set()
for file in (root/'samples').glob('*.shwork.json'):
    project=json.loads(file.read_text(encoding='utf-8'));assets=[]
    for ref,descriptor in project['asset_refs'].items():
        sha=descriptor['texture_sha256'];relative=descriptor['texture_ref'];path=file.parent/relative
        ok=relative=='assets/'+sha+'.png' and path.is_file()
        if ok:
            data=path.read_bytes();ok=hashlib.sha256(data).hexdigest()==sha and data[:8]==b'\x89PNG\r\n\x1a\n' and list(struct.unpack('>II',data[16:24]))==descriptor['texture_size_px']
        if not ok:failures.append(file.name+' missing/invalid dependency '+ref)
        assets.append(dict(ref=ref,passed=ok));referenced.add(relative)
    sample_rows.append(dict(path=str(file.relative_to(root)).replace('\\','/'),sha256=hashlib.sha256(file.read_bytes()).hexdigest(),input_hash=project['materialized_snapshot']['input_hash'],assets=assets))
unused=[str(f.relative_to(root/'samples')).replace('\\','/') for f in (root/'samples/assets').glob('*.png') if 'assets/'+f.name not in referenced]
if unused:failures.append('Unreferenced packaged PNG: '+str(unused))
result=dict(passed=not failures,failures=failures,preserved_baseline_files=preserved,explicit_baseline_changes=explicit_changes,samples=sample_rows,packaged_png_count=len(list((root/'samples/assets').glob('*.png'))),unused_pngs=unused)
if a.output:
    if a.output.exists():raise SystemExit('Refusing to overwrite evidence')
    a.output.parent.mkdir(parents=True,exist_ok=True);a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(dict(passed=result['passed'],preserved=len(preserved),samples=len(sample_rows),pngs=result['packaged_png_count'],failures=failures),ensure_ascii=False))
raise SystemExit(0 if result['passed'] else 1)
