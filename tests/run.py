"""Portable isolated regression runner. Results stay outside the upload scope."""
from pathlib import Path
import argparse,gzip,hashlib,io,json,os,re,shutil,subprocess,sys,tempfile,time,uuid,zipfile
root=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--godot',default=os.environ.get('GODOT_BIN') or shutil.which('godot4') or shutil.which('godot'));p.add_argument('--output',type=Path,required=True);p.add_argument('--script',action='append');p.add_argument('--suite');p.add_argument('--baseline',help='Replay a Git revision of addons in the disposable copy');p.add_argument('--graphical',action='store_true');p.add_argument('--timeout',type=int,default=120);p.add_argument('args',nargs=argparse.REMAINDER);a=p.parse_args()
if not a.godot:raise SystemExit('Provide --godot /path/to/godot or GODOT_BIN')
if a.output.exists():raise SystemExit('Refusing to overwrite test evidence')
a.output.mkdir(parents=True);files={str(f.relative_to(root)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in root.rglob('*') if f.is_file() and not any(x in {'.git','.godot','.test-runs','__pycache__'} for x in f.relative_to(root).parts) and f.suffix!='.import'}
rows=[]
isolated_changed=[]
with tempfile.TemporaryDirectory(prefix='newmap-regression-') as temp:
    copy=Path(temp)/'project';shutil.copytree(root,copy,ignore=shutil.ignore_patterns('.git','.godot','.test-runs','__pycache__','*.import'))
    if a.baseline:
        archive=subprocess.check_output(['git','-c','core.autocrlf=false','archive','--format=zip',a.baseline,'addons'],cwd=root)
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            for item in z.infolist():
                target=(copy/item.filename).resolve()
                if not target.is_relative_to((copy/'addons').resolve()):raise SystemExit('Unsafe archive member')
                if not item.is_dir():target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(z.read(item))
    cfg=copy/'project.godot';text=cfg.read_text(encoding='utf-8');text=re.sub(r'config/custom_user_dir_name="[^"]+"','config/custom_user_dir_name="newmap-test-'+uuid.uuid4().hex+'"',text);cfg.write_text(text,encoding='utf-8',newline='\n')
    isolated_hashes={name:hashlib.sha256((copy/name).read_bytes()).hexdigest() for name in files}
    core=Path(temp)/'fixture';core.mkdir()
    fixture=copy/'tests/fixtures/core.shwork.json.gz'
    if fixture.exists():
        (core/'core.shwork.json').write_bytes(gzip.decompress(fixture.read_bytes()));shutil.copytree(copy/'samples/assets',core/'assets')
    editing_fixture=copy/'tests/fixtures/editing_core.shwork.json.gz'
    if editing_fixture.exists():(core/'editing_core.shwork.json').write_bytes(gzip.decompress(editing_fixture.read_bytes()))
    pack=copy/'samples/reference_assets.assetpack.json'
    if pack.exists():
        reference=json.loads(pack.read_text(encoding='utf-8'))
        for name,tree in [('materials',False),('trees',True)]:
            subset={**reference,'assets':[item for item in reference['assets'] if (item['category']=='tree')==tree]}
            (core/(name+'.assetpack.json')).write_text(json.dumps(subset,ensure_ascii=False),encoding='utf-8')
    cases=json.loads((root/'tests/suites.json').read_text(encoding='utf-8'))[a.suite] if a.suite else [dict(script=s) for s in (a.script or ['tests/review_c7e0/test_review_contracts.gd'])]
    for i,case in enumerate(cases):
        script=case['script'];graphical=case.get('graphical',a.graphical)
        cmd=[a.godot]+([] if graphical else ['--headless'])+['--path',str(copy),'--log-file',str(a.output.resolve()/(str(i)+'.native.log')),'--script','res://'+script]
        if case.get('kind')=='editor':cmd=[a.godot,'--headless','--editor','--quit','--path',str(copy),'--log-file',str(a.output.resolve()/(str(i)+'.native.log'))]
        artifacts=a.output.resolve()/(str(i)+'-artifacts');artifacts.mkdir()
        args=case.get('args',a.args);args=args[1:] if args and args[0]=='--' else args
        args=[arg.replace('{source}',str(copy).replace('\\','/')).replace('{artifacts}',str(artifacts).replace('\\','/')).replace('{core_fixture}',str(core/'core.shwork.json').replace('\\','/')).replace('{editing_fixture}',str(core/'editing_core.shwork.json').replace('\\','/')).replace('{material_fixture}',str(core/'materials.assetpack.json').replace('\\','/')).replace('{tree_fixture}',str(core/'trees.assetpack.json').replace('\\','/')) for arg in args]
        if args:cmd+=['--',*args]
        start=time.perf_counter()
        try:
            proc=subprocess.Popen(cmd,cwd=copy,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:raw_out,raw_err=proc.communicate(timeout=case.get('timeout',a.timeout));code=proc.returncode
            except subprocess.TimeoutExpired:
                # The Windows console binary launches the GUI binary; terminate
                # this test's process tree so inherited pipes cannot hang cleanup.
                if os.name=='nt':subprocess.run(['taskkill','/PID',str(proc.pid),'/T','/F'],capture_output=True)
                else:proc.kill()
                raw_out,raw_err=proc.communicate(timeout=10);raw_err+=b'\nTIMEOUT';code=124
            stdout=raw_out.decode('utf-8','replace');stderr=raw_err.decode('utf-8','replace')
        except OSError as exc:stdout='';stderr=str(exc);code=127
        (a.output/(str(i)+'.stdout.txt')).write_text(stdout,encoding='utf-8');(a.output/(str(i)+'.stderr.txt')).write_text(stderr,encoding='utf-8')
        row=dict(script=script,command=cmd,exit_code=code,seconds=time.perf_counter()-start,passed=code==0 and 'SCRIPT ERROR:' not in stderr and 'ERROR:' not in stderr and 'destroyed without its completion' not in stderr and 'Unicode parsing error' not in stderr);rows.append(row);print(json.dumps(row),flush=True);print(stdout[-4500:],stderr[-3500:],flush=True)
    isolated_changed=[name for name,digest in isolated_hashes.items() if not (copy/name).is_file() or hashlib.sha256((copy/name).read_bytes()).hexdigest()!=digest]
changed=[name for name,digest in files.items() if not (root/name).is_file() or hashlib.sha256((root/name).read_bytes()).hexdigest()!=digest]
record=dict(passed=all(r['passed'] for r in rows) and not isolated_changed,scope='isolated Godot project and private user directory',baseline_revision=a.baseline,source_sha256=files,isolated_source_sha256=isolated_hashes,source_changed_during_run=changed,isolated_source_changed=isolated_changed,tests=rows)
(a.output/'RESULT.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8');raise SystemExit(0 if record['passed'] else 1)
