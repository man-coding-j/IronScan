import {bundle} from '@remotion/bundler';
import {openBrowser,selectComposition,renderMedia} from '@remotion/renderer';
import {config} from '../src/config.ts';
const serveUrl=await bundle({entryPoint:'src/index.ts'});
const browser=await openBrowser('chrome');
try {
  const composition=await selectComposition({serveUrl,id:config.video.id,puppeteerInstance:browser});
  let last=-1;
  await renderMedia({serveUrl,composition,puppeteerInstance:browser,
    outputLocation:config.output.video,codec:'h264',pixelFormat:'yuv420p',crf:16,
    imageFormat:'jpeg',jpegQuality:95,concurrency:4,muted:true,
    onProgress:({progress})=>{const percent=Math.floor(progress*10)*10;if(percent!==last){console.log(`Render ${percent}%`);last=percent;}},
  });
  console.log(`Saved ${config.output.video}`);
} finally {await browser.close({silent: true});}
