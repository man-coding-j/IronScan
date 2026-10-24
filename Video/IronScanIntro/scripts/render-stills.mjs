import {bundle} from '@remotion/bundler';
import {selectComposition,renderStill,openBrowser} from '@remotion/renderer';
import {mkdir} from 'node:fs/promises';
import {config} from '../src/config.ts';
const serveUrl=await bundle({entryPoint:'src/index.ts'});
const browser=await openBrowser('chrome');
try {
  const composition=await selectComposition({serveUrl,id:config.video.id,puppeteerInstance:browser});
  await mkdir(config.output.stills,{recursive:true});
  for(const frame of config.output.reviewFrames) {
    await renderStill({serveUrl,composition,frame,output:`${config.output.stills}/${frame}.png`,puppeteerInstance:browser});
    console.log(`Rendered frame ${frame}`);
  }
} finally {await browser.close({silent: true});}
