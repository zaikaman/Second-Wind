// The migration runner reads `*.sql` from its own directory at runtime, so `dist` needs the files
// that `tsc` does not emit. Keeping the copy in the build script means `npm start` and any
// container image built from `dist` behave the same as `npm run dev`.
import { cp, mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const apiRoot = join(here, '..');
const from = join(apiRoot, 'src', 'db', 'migrations');
const to = join(apiRoot, 'dist', 'db', 'migrations');

await mkdir(to, { recursive: true });
await cp(from, to, { recursive: true });
process.stdout.write(`copied migrations to ${to}\n`);
