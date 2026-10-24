import {existsSync} from 'node:fs';
import {config} from '../src/config.ts';
const files = [...config.copy.screens.map(screen=>screen.file),config.assets.login];
let missing = false;
for(const file of files) {
  const path = config.assets.screenshots+file;
  const found = existsSync(new URL(`../public/${path}`,import.meta.url));
  console.log(`${found ? 'OK' : 'MISSING'} ${path}`);
  missing ||= !found;
}
process.exitCode = missing ? 1 : 0;
