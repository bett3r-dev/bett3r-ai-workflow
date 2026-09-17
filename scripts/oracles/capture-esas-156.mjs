#!/usr/bin/env node
// Capture driver for stage 7 of scripts/oracles/epic-esas-156.sh (ESAS-174
// design.md P4). Produces the files `design-map select` and `design-map post`
// read, from a REAL esas checkout rather than hand-copied fixtures.
//
//   node capture-esas-156.mjs <esas-checkout> <map.json> <captures-dir> <repo-dir>
//
// <repo-dir> must not exist: it is created, `git init`ed, and left with no
// `.esas/` until `start_map_session` makes one. <map.json> is the plugin map
// whose nodes, forks and statuses are replayed into the store.
//
// esas's own launcher (packages/esas-mcp/bin/esas-mcp.mjs) runs the TypeScript
// sources through tsx, and its workspace packages export `./src/index.ts`, so
// the tsc build output cannot resolve them under plain node. This driver does
// what that launcher does: register tsx, then import `src/server.ts`. The
// server is reached over the SDK's InMemoryTransport, as
// packages/esas-mcp/oracles/epic-esas-156.oracle.test.ts does.
//
// Written files:
//   tools.txt    listTools names, one per line
//   status.json  `status` before start_map_session (the ESAS_DIR_MISSING envelope)
//   start.json   `start_map_session`
//   getmap.json  `get_map` after the replay
//   board.json   the one synthesized capture: readBoardStatus's body shape
//                (sticky-notes-board board-identity.ts) with esas's BOARD_KINDS,
//                repoPath = <repo-dir>; no vite board is run
//   pwd.txt      <repo-dir> as given, then its realpath
//
// Any failure exits non-zero with one `capture-failed:` line on stderr.

import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, realpathSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const [ esas, mapPath, captures, repo ] = process.argv.slice( 2 );
if ( !esas || !mapPath || !captures || !repo ){
  process.stderr.write( 'capture-failed: usage: capture-esas-156.mjs <esas-checkout> <map.json> <captures-dir> <repo-dir>\n' );
  process.exit( 2 );
}

const fromMcp = createRequire( join( esas, 'packages', 'esas-mcp', 'package.json' ));
const { register } = await import( pathToFileURL( fromMcp.resolve( 'tsx/esm/api' )).href );
register();

const { Client } = await import( pathToFileURL( fromMcp.resolve( '@modelcontextprotocol/sdk/client/index.js' )).href );
const { InMemoryTransport } = await import( pathToFileURL( fromMcp.resolve( '@modelcontextprotocol/sdk/inMemory.js' )).href );
const { createEsasMcpServer } = await import( pathToFileURL( join( esas, 'packages', 'esas-mcp', 'src', 'server.ts' )).href );
const { createEsasStore, BOARD_KINDS } = await import( pathToFileURL( join( esas, 'packages', 'esas-store', 'src', 'index.ts' )).href );

mkdirSync( repo );
execFileSync( 'git', [ 'init', '-q' ], { cwd: repo });
mkdirSync( captures, { recursive: true });

const server = createEsasMcpServer({ repoPath: repo });
const [ clientTransport, serverTransport ] = InMemoryTransport.createLinkedPair();
const client = new Client({ name: 'capture-esas-156', version: '0.0.0' });
await Promise.all( [ server.connect( serverTransport ), client.connect( clientTransport ) ] );

/** The first text block of a tool result, parsed. */
async function call( name, args = {}){
  const result = await client.callTool({ name, arguments: args });
  const first = result.content?.[ 0 ];
  if ( first?.type !== 'text' ) throw new Error( `${ name }: no text content block` );
  return JSON.parse( first.text );
}

/** A call whose body must be `ok: true`. */
async function must( name, args ){
  const body = await call( name, args );
  if ( body.ok !== true ) throw new Error( `${ name } ${ JSON.stringify( args ) } refused: ${ JSON.stringify( body.error ?? body ) }` );
  return body;
}

const put = ( file, text ) => writeFileSync( join( captures, file ), text );

const tools = ( await client.listTools()).tools.map( tool => tool.name );
put( 'tools.txt', tools.join( '\n' ) + '\n' );
put( 'status.json', JSON.stringify( await call( 'status' ), null, 2 ));
put( 'start.json', JSON.stringify( await call( 'start_map_session' ), null, 2 ));

const map = JSON.parse( readFileSync( mapPath, 'utf8' ));
await must( 'map_ground', { shape: map.shape });
for ( const node of map.nodes ){
  await must( 'map_post', { level: node.level, id: node.id, title: node.title, parents: node.parents });
}
for ( const fork of map.forks ){
  await must( 'map_post', {
    level: 'fork', id: fork.id, title: fork.title,
    ...( fork.card ? { card: fork.card } : {}),
    ...( fork.anchor ? { anchor: fork.anchor } : {}),
    ...( fork.restsOn ? { restsOn: fork.restsOn } : {}),
    ...( fork.testable === false ? { testable: false } : {})
  });
}

// Statuses. `recommendation` and `code` are the agent's answers, so they go
// through `map_choose`. `owner` is the human's: `map_choose` stamps author
// 'ai' and can never record it (ESAS-168), and the board's own route
// (sticky-notes-board map-routes.ts) records it by calling the store's
// `mapChoose` with author 'human' — the same call this driver makes.
const store = createEsasStore({ repoPath: repo });
for ( const fork of map.forks ){
  const status = fork.status;
  if ( status.kind === 'open' ) continue;
  if ( status.kind === 'moot' ){
    await must( 'map_strike', { id: fork.id, reason: status.reason });
    continue;
  }
  if ( status.kind !== 'decided' ) throw new Error( `${ fork.id }: unhandled status kind ${ status.kind }` );
  const { mapSeq } = await must( 'get_map' );
  if ( status.source === 'owner' ){
    await store.mapChoose({ fork: fork.id, option: status.option, seenSeq: mapSeq, author: 'human' });
  } else {
    await must( 'map_choose', {
      fork: fork.id, option: status.option, seenSeq: mapSeq,
      ...( status.source === 'code' ? { settledBy: 'code' } : {})
    });
  }
}

const read = await must( 'get_map' );
put( 'getmap.json', JSON.stringify( read, null, 2 ));

let gitSha = 'unknown';
try {
  gitSha = execFileSync( 'git', [ 'rev-parse', 'HEAD' ], { cwd: repo, stdio: [ 'ignore', 'pipe', 'ignore' ] }).toString().trim() || 'unknown';
} catch {
  // No commits yet: readTargetGitSha answers UNKNOWN_SHA ('unknown') too.
}
put( 'board.json', JSON.stringify({
  repoPath: repo, gitSha, lastSeq: read.mapSeq, sessions: 1, anchored: false, boardKinds: [ ...BOARD_KINDS ]
}, null, 2 ));
put( 'pwd.txt', `${ repo }\n${ realpathSync( repo ) }\n` );

await client.close();
