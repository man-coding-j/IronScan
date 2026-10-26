import {bundle} from '@remotion/bundler';
import {openBrowser,selectComposition,renderStill} from '@remotion/renderer';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
import {config} from '../src/config.ts';
const serveUrl=await bundle({entryPoint:'src/index.ts'});
const browser=await openBrowser('chrome');
const directory=resolve(config.output.readmeAssets.directory);
try {
  await mkdir(directory,{recursive:true});
  const composition=await selectComposition({serveUrl,id:config.video.id,puppeteerInstance:browser});
  const assets=[];
  for(const shot of config.output.readmeAssets.shots) {
    const frame=Math.round(shot.second*config.video.fps);
    const output=resolve(directory,shot.file);
    await renderStill({serveUrl,composition,frame,output,puppeteerInstance:browser,imageFormat:'png'});
    const bytes=await readFile(output);
    const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);
    if(width!==1920||height!==1080)throw new Error(`Unexpected dimensions: ${shot.file}`);
    assets.push({...shot,frame,width,height,sha256:createHash('sha256').update(bytes).digest('hex')});
    console.log(`Exported ${shot.file} at ${shot.second}s / frame ${frame} (${width}x${height})`);
  }
  await writeFile(resolve(directory,'manifest.json'),JSON.stringify({source:'IronScanIntro Remotion composition',fps:config.video.fps,content:'Fictional data and original vector UI illustrations; not clinical evidence',assets},null,2)+'\n');
} finally {await browser.close({silent:true});}
