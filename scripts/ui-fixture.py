"""Start an isolated GUI with deliberately large counts; never opens the user's DB or input monitor."""
from pathlib import Path
import os, plistlib, shutil, sqlite3, subprocess, tempfile, time
root=Path(__file__).resolve().parent.parent
artifact=root/'output/verification'
artifact.mkdir(parents=True,exist_ok=True)
state=Path(tempfile.mkdtemp(prefix='mactoys-ui-'))
app=artifact/'MacToys Test.app'
if app.exists(): shutil.rmtree(app)
shutil.copytree(root/'InputStats.app',app)
p=app/'Contents/Info.plist'
d=plistlib.loads(p.read_bytes()); d['CFBundleIdentifier']='com.local.mactoys.tests'; d['CFBundleDisplayName']='MacToys Test'; d['CFBundleName']='MacToys Test'; p.write_bytes(plistlib.dumps(d))
subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
with sqlite3.connect(state/'stats.sqlite') as db:
 db.execute('CREATE TABLE minute_stats (bucket_start INTEGER PRIMARY KEY, keyboard_chars INTEGER, keyboard_words INTEGER, voice_chars INTEGER, voice_words INTEGER)')
 db.execute('INSERT INTO minute_stats VALUES (?, ?, ?, ?, ?)',(int(time.time())//60*60,12_345_678,123_456,98_765,23_456))
log=(artifact/'ui-fixture.log').open('w')
proc=subprocess.Popen([str(app/'Contents/MacOS/InputStats')],env=dict(os.environ,INPUTSTATS_TEST_HOME=str(state)),stdout=log,stderr=log,start_new_session=True)
(artifact/'fixture-state.txt').write_text(str(state))
(artifact/'fixture-pid.txt').write_text(str(proc.pid))
print('GUI fixture PID:',proc.pid,'State:',state)
