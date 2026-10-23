// Run once on the Mac used to build this private app. No secret is stored in Git or logs.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = fileURLToPath(new URL('../../', import.meta.url));
const directory = path.join(root, 'frontend/ios/App/Private');
const destination = path.join(directory, 'GymPersonalConnection.json');
const temporary = path.join(directory, `.connection-${process.pid}.json`);
try {
  const args = process.argv.slice(2);
  if (args.length > 2 || (args.length && !['--file', '--host'].includes(args[0])) || (args.length === 1)) throw new Error();
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  if (args[0] === '--file') fs.copyFileSync(args[1], temporary);
  else {
    const host = args[1] || 'lin-server@10.100.5.110';
    if (!/^[A-Za-z0-9_][A-Za-z0-9_.@-]*$/.test(host)) throw new Error();
    const result = spawnSync('scp', [`${host}:.config/opengym/GymPersonalConnection.json`, temporary], { stdio: 'inherit' });
    if (result.status !== 0) throw new Error();
  }
  const config = JSON.parse(fs.readFileSync(temporary, 'utf8'));
  const base = new URL(config.base);
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash ||
      typeof config.userID !== 'string' || !config.userID || typeof config.name !== 'string' ||
      typeof config.token !== 'string' || !/^ios:[^:]+:\d+:[a-f0-9]{64}\.[A-Za-z0-9_-]{43}$/.test(config.token)) throw new Error();
  fs.chmodSync(temporary, 0o600);
  fs.renameSync(temporary, destination);
  console.log('Personal connection is ready. Build and run in Xcode; the app will sync automatically.');
} catch {
  console.error('Personal setup failed. Check SSH access to H3, or use --file PATH with your private configuration. No credential was printed.');
  process.exitCode = 1;
} finally {
  if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
}
