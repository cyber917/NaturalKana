#!/usr/bin/env python3
"""Restore pinned upstreams and apply reviewed patches. Does not overwrite existing edits."""
from pathlib import Path
import argparse, json, subprocess, os, shutil
ROOT=Path(__file__).resolve().parents[1]
PINS={'ios':('azooKey-ios','https://github.com/azooKey/azooKey.git','b50db4aec1069a8d2341f70415da3bdc61f1fce6'), 'macos':('azooKey-macos','https://github.com/azooKey/azooKey-Desktop.git','bd90b7bdc8f38069987b36426b990ef3129edf62')}
def run(args,cwd=None,**kwargs):return subprocess.run(args,cwd=cwd,check=True,**kwargs)
def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--weights',action='store_true',help='Download Git LFS model weights (large)');args=parser.parse_args()
 env=os.environ.copy();env['GIT_LFS_SKIP_SMUDGE']='1'
 for platform,(folder,url,revision) in PINS.items():
  destination=ROOT/'upstream'/folder
  if not destination.exists():
   run(['git','clone','--no-checkout',url,str(destination)],env=env)
   run(['git','checkout','--detach',revision],cwd=destination,env=env)
   run(['git','submodule','update','--init','--recursive'],cwd=destination,env=env)
  else:
   actual=subprocess.check_output(['git','rev-parse','HEAD'],cwd=destination,text=True).strip()
   if actual!=revision:raise SystemExit(f'{folder}: unexpected revision; existing checkout preserved')
  patch=ROOT/'patches'/f'{platform}.patch'
  if subprocess.run(['git','apply','--reverse','--check',str(patch)],cwd=destination,capture_output=True).returncode!=0:
   run(['git','apply','--check',str(patch)],cwd=destination)
   run(['git','apply',str(patch)],cwd=destination)
  lock=ROOT/'Config/Dependencies'/f'{platform}.resolved'
  if lock.exists():shutil.copy2(lock,destination/('AzooKeyCore' if platform=='ios' else 'Core')/'Package.resolved')
  if args.weights:
   if subprocess.run(['git','lfs','version'],capture_output=True).returncode:raise SystemExit('Install git-lfs and rerun --weights')
   run(['git','submodule','foreach','--recursive','git lfs pull'],cwd=destination)
 print('Pinned sources ready. Open NaturalKana.xcworkspace using full Xcode; configure your signing team.')
if __name__=='__main__':main()
