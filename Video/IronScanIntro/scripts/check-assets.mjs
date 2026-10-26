import {existsSync} from 'node:fs';
import {config} from '../src/config.ts';
const files = [...new Set(config.copy.screens.map(screen=>screen.file).filter(Boolean))];
let missing = false;
for(const file of files) {
  const path = config.assets.screenshots+file;
  const found = existsSync(new URL(`../public/${path}`,import.meta.url));
  console.log(`${found ? 'OK' : 'MISSING'} ${path}`);
  missing ||= !found;
}
process.exitCode = missing ? 1 : 0;
