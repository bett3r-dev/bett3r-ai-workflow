import { Connector, MiroApi, Item, CardItem, Tag, AppCardItem } from '@mirohq/miro-api';
import { WidgetDataOutput, StickyNoteItem } from '@mirohq/miro-api/dist/api';
import * as dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';

// MIRO_ACCESS_TOKEN resolution — a real environment variable always wins (dotenv does not
// override values already in process.env). Otherwise fall back to a `.env` in the directory you
// run the command from, then a `.env` beside this script. Prefer a shell/exported env var: it
// works regardless of cwd and survives plugin updates (this script's dir is wiped on update).
dotenv.config();                                          // ./.env (current working directory)
dotenv.config({ path: path.join( __dirname, '.env' ) });  // <script-dir>/.env (fallback)

const miro = new MiroApi( process.env.MIRO_ACCESS_TOKEN as string );

// Color to artifact type mapping
const COLOR_TO_ARTIFACT_TYPE: Record<string, string> = {
  gray: 'UI',
  blue: 'Command',
  light_yellow: 'Aggregate',
  orange: 'Event',
  light_green: 'ReadModel',
  violet: 'Policy'
};

const getArtifactType = ( color: string ): string => {
  return COLOR_TO_ARTIFACT_TYPE[color] || 'External';
};

// Allowed edge patterns for validation
const ALLOWED_EDGES = new Set([
  'UI->Command',
  'Command->Aggregate',
  'Aggregate->Event',
  'Aggregate->Database',
  'Event->Policy',
  'Event->ReadModel',
  'Policy->Command',
  'Policy->Database',
  'ReadModel->UI',
  'ReadModel->Database',
  'Command->Invariant',
  'Invariant->Aggregate'
]);

type CalloutSemantic = 'hotspot' | 'info' | 'idea';

interface CalloutAttachment {
  text: string;
  semantic: CalloutSemantic;
  strokeColor: string;
}

interface PreprocessedItem {
  id: string;
  type: string;
  text: string;
  description?: string;
  color?: string;
  x: number;
  y: number;
  width: number;
  height: number;
  tags?: string[];
  artifactType?: string;
  isMinSticky?: boolean;
  parentOverlap?: string;
  dataStructure?: {
    content: string;
  };
  callouts?: {
    hotspots: string[];
    info: string[];
    ideas: string[];
  };
}

interface PreprocessedConnector {
  id: string;
  from: string;
  to: string;
  fromType?: string;
  toType?: string;
  isValid?: boolean;
  validationError?: string;
}

// ====================
// SVG parsing (callouts + code blocks + svg connectors)
// ====================

interface SvgCallout {
  text: string;
  semantic: CalloutSemantic;
  strokeColor: string;
  x: number;
  y: number;
  width: number;
  height: number;
  tailTipX: number;
  tailTipY: number;
}

interface SvgCodeBlock {
  id: string; // synthetic id
  content: string;
  x: number;
  y: number;
  width: number;
  height: number;
}

interface SvgConnector {
  startX: number;
  startY: number;
  endX: number;
  endY: number; // arrowhead tip
}

const decodeXmlEntities = ( s: string ): string => {
  return s
    .replace( /&amp;/g, '&' )
    .replace( /&lt;/g, '<' )
    .replace( /&gt;/g, '>' )
    .replace( /&quot;/g, '"' )
    .replace( /&#39;/g, '\'' )
    .replace( /&#(\d+);/g, ( _m, code: string ) => String.fromCharCode( Number( code )));
};

const stripTags = ( s: string ): string => s.replace( /<[^>]*>/g, '' );

const classifyCalloutColor = ( hex: string ): CalloutSemantic | 'unknown' => {
  const h = hex.replace( '#', '' );
  if ( h.length < 6 ) return 'unknown';
  const r = parseInt( h.slice( 0, 2 ), 16 );
  const g = parseInt( h.slice( 2, 4 ), 16 );
  const b = parseInt( h.slice( 4, 6 ), 16 );

  // Dominant-channel classification with tolerance for off-pure hues
  if ( r > g + 30 && r > b + 30 ) return 'hotspot';
  if ( g > r + 30 && g > b + 30 ) return 'idea';
  if ( b > r + 30 && b > g + 30 ) return 'info';
  // Fallback heuristics for mixed colors
  if ( r > 200 && g < 150 && b < 150 ) return 'hotspot';
  if ( g > 160 && r < 180 && b < 180 ) return 'idea';
  if ( b > 160 && r < 180 && g < 180 ) return 'info';
  return 'unknown';
};

// Iterate top-level item-shaped groups: `<g width="..." height="..." transform="translate(x, y) scale(s)...">`
function* iterateItemGroups( svg: string ): Generator<{
  fullMatch: string;
  inner: string;
  x: number;
  y: number;
  scale: number;
  width: number;
  height: number;
  endIndex: number;
}> {
  const re = /<g\s+width="([\d.]+)px"\s+height="([\d.]+)px"\s+transform="translate\(([-\d.]+),\s*([-\d.]+)\)\s*scale\(([\d.]+)\)[^"]*">/g;
  let m: RegExpExecArray | null;
  while (( m = re.exec( svg )) !== null ) {
    const width = parseFloat( m[1]);
    const height = parseFloat( m[2]);
    const x = parseFloat( m[3]);
    const y = parseFloat( m[4]);
    const scale = parseFloat( m[5]);
    // Walk forward to find balanced closing </g> for this opening tag
    let depth = 1;
    const tagRe = /<g\b|<\/g>/g;
    tagRe.lastIndex = re.lastIndex;
    let endIdx = -1;
    let t: RegExpExecArray | null;
    while (( t = tagRe.exec( svg )) !== null ) {
      if ( t[0] === '</g>' ) {
        depth--;
        if ( depth === 0 ) { endIdx = t.index + t[0].length; break; }
      } else {
        depth++;
      }
    }
    if ( endIdx === -1 ) continue;
    const inner = svg.slice( re.lastIndex, endIdx - '</g>'.length );
    yield { fullMatch: m[0], inner, x, y, scale, width, height, endIndex: endIdx };
    re.lastIndex = endIdx;
  }
}

function extractTextNodes( inner: string ): string {
  // Pull every <text ...>content</text>, decode entities, strip nested tags, join with spaces.
  const re = /<text\b[^>]*>([\s\S]*?)<\/text>/g;
  const parts: string[] = [];
  let m: RegExpExecArray | null;
  while (( m = re.exec( inner )) !== null ) {
    const raw = decodeXmlEntities( stripTags( m[1]));
    if ( raw.length > 0 ) parts.push( raw );
  }
  return parts.join( ' ' ).replace( /\s+/g, ' ' )
.trim();
}

function extractTextNodesPreservingLines( inner: string ): string {
  // For code blocks: each <text> gets its own line. Concatenate text nodes with same y.
  const re = /<text\b[^>]*\sy="([\d.]+)"[^>]*>([\s\S]*?)<\/text>/g;
  const rows: { y: number; text: string }[] = [];
  let m: RegExpExecArray | null;
  while (( m = re.exec( inner )) !== null ) {
    const y = parseFloat( m[1]);
    const raw = decodeXmlEntities( stripTags( m[2]));
    if ( raw.length === 0 ) continue;
    const existing = rows.find( r => Math.abs( r.y - y ) < 2 );
    if ( existing ) existing.text += raw;
    else rows.push({ y, text: raw });
  }
  rows.sort(( a, b ) => a.y - b.y );
  return rows.map( r => r.text ).join( '\n' );
}

function parseCalloutPath( pathD: string, width: number, height: number ): { tipX: number; tipY: number } | null {
  // Look for any absolute L command whose coords are outside the rounded-rectangle body.
  const re = /[ML]\s*([-\d.]+)[\s,]+([-\d.]+)/g;
  let m: RegExpExecArray | null;
  let best: { x: number; y: number; distance: number } | null = null;
  while (( m = re.exec( pathD )) !== null ) {
    const x = parseFloat( m[1]);
    const y = parseFloat( m[2]);
    const outsideY = y > height + 2 || y < -2;
    const outsideX = x > width + 2 || x < -2;
    if ( !outsideX && !outsideY ) continue;
    const dy = y > height ? y - height : ( y < 0 ? -y : 0 );
    const dx = x > width ? x - width : ( x < 0 ? -x : 0 );
    const distance = Math.max( dx, dy );
    if ( !best || distance > best.distance ) best = { x, y, distance };
  }
  if ( !best ) return null;
  return { tipX: best.x, tipY: best.y };
}

function parseSvg( svgPath: string ): {
  callouts: SvgCallout[];
  codeBlocks: SvgCodeBlock[];
  connectors: SvgConnector[];
} {
  const svg = fs.readFileSync( svgPath, 'utf8' );
  const callouts: SvgCallout[] = [];
  const codeBlocks: SvgCodeBlock[] = [];
  const connectors: SvgConnector[] = [];

  let codeBlockCounter = 0;

  // Pass 1: index every item group by transform position. Code blocks emit two
  // sibling groups at the same position (background <svg>, then a text <g>); we
  // need to merge them.
  type GroupSlot = {
    x: number;
    y: number;
    width: number;
    height: number;
    isCodeBlockBg: boolean;
    text: string;
  };
  const slotsByPos = new Map<string, GroupSlot>();

  const groupsIterator = iterateItemGroups( svg );
  let groupStep = groupsIterator.next();
  while ( !groupStep.done ) {
    const grp = groupStep.value;
    const key = `${grp.x.toFixed( 2 )}|${grp.y.toFixed( 2 )}`;
    const slot = slotsByPos.get( key ) ?? {
      x: grp.x,
      y: grp.y,
      width: grp.width * grp.scale,
      height: grp.height * grp.scale,
      isCodeBlockBg: false,
      text: ''
    };

    const hasCodeBlockBg = /fill="#050038"/i.test( grp.inner );
    if ( hasCodeBlockBg ) slot.isCodeBlockBg = true;

    // Callout check (only emit once per position)
    const styleMatch = grp.inner.match( /style="[^"]*stroke:\s*(#[0-9a-fA-F]{3,6})[^"]*"/ );
    const pathMatch = grp.inner.match( /<path\s+d="([^"]+)"/ );
    if ( !hasCodeBlockBg && styleMatch && pathMatch ) {
      const tip = parseCalloutPath( pathMatch[1], grp.width, grp.height );
      if ( tip ) {
        const strokeColor = styleMatch[1];
        const semantic = classifyCalloutColor( strokeColor );
        if ( semantic !== 'unknown' ) {
          const text = extractTextNodes( grp.inner );
          callouts.push({
            text,
            semantic,
            strokeColor,
            x: grp.x,
            y: grp.y,
            width: grp.width * grp.scale,
            height: grp.height * grp.scale,
            tailTipX: grp.x + tip.tipX * grp.scale,
            tailTipY: grp.y + tip.tipY * grp.scale
          });
        }
      }
    }

    // Collect text content (we'll only emit if the slot is also marked as code-block bg)
    if ( !hasCodeBlockBg && /<text\b/.test( grp.inner )) {
      const text = extractTextNodesPreservingLines( grp.inner );
      if ( text.length > slot.text.length ) slot.text = text;
    }

    slotsByPos.set( key, slot );
    groupStep = groupsIterator.next();
  }

  slotsByPos.forEach(( slot ) => {
    if ( !slot.isCodeBlockBg ) return;
    if ( slot.text.length === 0 ) return;
    codeBlocks.push({
      id: `svg-codeblock-${++codeBlockCounter}`,
      content: slot.text,
      x: slot.x,
      y: slot.y,
      width: slot.width,
      height: slot.height
    });
  });

  // Connectors: <g width="0px" height="..."> with a <path> and a <use xlink:href="#LineHeadArrow...">
  const connectorRe = /<g\s+width="0px"\s+height="([\d.]+)px"\s+transform="translate\(([-\d.]+),\s*([-\d.]+)\)[^"]*">([\s\S]*?)<\/g>/g;
  let cm: RegExpExecArray | null;
  while (( cm = connectorRe.exec( svg )) !== null ) {
    const inner = cm[4];
    if ( !/LineHeadArrow/i.test( inner )) continue;
    const tx = parseFloat( cm[2]);
    const ty = parseFloat( cm[3]);
    // Start of the path: capture the first M command's coords (space or comma separated).
    const pathStartMatch = inner.match( /<path[^>]*\sd="\s*M\s*([-\d.eE+]+)[ ,]\s*([-\d.eE+]+)/ );
    const useMatch = inner.match( /<use[^>]*xlink:href="#LineHeadArrow[^"]*"[^>]*transform="translate\(([-\d.eE+]+),\s*([-\d.eE+]+)\)/ );
    if ( !pathStartMatch ) continue;
    const sx = parseFloat( pathStartMatch[1]);
    const sy = parseFloat( pathStartMatch[2]);
    // Arrowhead tip: `<use>` transform position (local). Fall back to path start if missing.
    const tipLocalX = useMatch ? parseFloat( useMatch[1]) : sx;
    const tipLocalY = useMatch ? parseFloat( useMatch[2]) : sy;
    const start = { x: sx, y: sy };
    connectors.push({
      startX: tx + start.x,
      startY: ty + start.y,
      endX: tx + tipLocalX,
      endY: ty + tipLocalY
    });
  }

  return { callouts, codeBlocks, connectors };
}

// ====================
// Merge helpers
// ====================

function bboxContains( item: PreprocessedItem, px: number, py: number ): boolean {
  const left = item.x - item.width / 2;
  const right = item.x + item.width / 2;
  const top = item.y - item.height / 2;
  const bottom = item.y + item.height / 2;
  return px >= left && px <= right && py >= top && py <= bottom;
}

function pointNearBbox( px: number, py: number, x: number, y: number, w: number, h: number, tolerance = 20 ): boolean {
  const left = x - tolerance;
  const right = x + w + tolerance;
  const top = y - tolerance;
  const bottom = y + h + tolerance;
  return px >= left && px <= right && py >= top && py <= bottom;
}

function attachCallouts( items: PreprocessedItem[], callouts: SvgCallout[]): void {
  for ( const callout of callouts ) {
    let target: PreprocessedItem | undefined;
    for ( const item of items ) {
      if ( bboxContains( item, callout.tailTipX, callout.tailTipY )) {
        target = item;
        break;
      }
    }
    if ( !target ) {
      console.error( `Warning: callout tail tip (${callout.tailTipX.toFixed( 1 )}, ${callout.tailTipY.toFixed( 1 )}) [${callout.semantic}] "${callout.text.slice( 0, 40 )}..." did not hit any item bbox` );
      continue;
    }
    if ( !target.callouts ) target.callouts = { hotspots: [], info: [], ideas: []};
    if ( callout.semantic === 'hotspot' ) target.callouts.hotspots.push( callout.text );
    else if ( callout.semantic === 'info' ) target.callouts.info.push( callout.text );
    else target.callouts.ideas.push( callout.text );
  }
}

function attachCodeBlocks(
  items: PreprocessedItem[],
  apiConnectors: PreprocessedConnector[],
  codeBlocks: SvgCodeBlock[]
): Set<string> {
  // Returns the set of API code-item IDs whose content has been merged into a
  // sticky's dataStructure (caller filters them from the output).
  const codeItemIdsConsumed = new Set<string>();
  for ( const block of codeBlocks ) {
    // Miro API reports stickies' position as their center, but code items as
    // their top-left. Match against either to be safe.
    const blockCx = block.x + block.width / 2;
    const blockCy = block.y + block.height / 2;
    const apiCodeItem = items.find( item =>
      item.type === 'code' && (
        ( Math.abs( item.x - blockCx ) < 10 && Math.abs( item.y - blockCy ) < 10 )
          || ( Math.abs( item.x - block.x ) < 10 && Math.abs( item.y - block.y ) < 10 )
      ));
    if ( !apiCodeItem ) {
      console.error( `Warning: SVG code block at (${block.x.toFixed( 1 )}, ${block.y.toFixed( 1 )}) has no matching API code item` );
      continue;
    }
    const connector = apiConnectors.find( c => c.from === apiCodeItem.id || c.to === apiCodeItem.id );
    if ( !connector ) {
      console.error( `Warning: API code item ${apiCodeItem.id} not connected to any sticky` );
      continue;
    }
    const otherId = connector.from === apiCodeItem.id ? connector.to : connector.from;
    const sticky = items.find( i => i.id === otherId );
    if ( !sticky ) continue;
    sticky.dataStructure = { content: block.content };
    codeItemIdsConsumed.add( apiCodeItem.id );
  }
  return codeItemIdsConsumed;
}

function findCalloutBodyShapeIds( items: PreprocessedItem[], callouts: SvgCallout[]): Set<string> {
  // Miro's API returns the callout body as an empty `shape` item at the same
  // position as the callout. Identify and filter them out of the final output.
  const ids = new Set<string>();
  for ( const callout of callouts ) {
    const cx = callout.x + callout.width / 2;
    const cy = callout.y + callout.height / 2;
    const match = items.find( item =>
      item.type !== 'sticky_note'
        && item.type !== 'code'
        && !item.text
        && Math.abs( item.x - cx ) < 10
        && Math.abs( item.y - cy ) < 10
        && Math.abs( item.width - callout.width ) < 10
        && Math.abs( item.height - callout.height ) < 10 );
    if ( match ) ids.add( match.id );
  }
  return ids;
}

// ====================
// Existing helpers (unchanged or lightly adjusted)
// ====================

const formatTextContent = ( content: string ): string => {
  return content
    .replace( /<br\s*\/?>/gi, '\n' )
    .replace( /<[^>]*>?/g, '' );
};

const formatItem = async ( item: Item ): Promise<Omit<PreprocessedItem, 'isMinSticky' | 'parentOverlap' | 'dataStructure' | 'callouts'>> => {
  const data = item.data as WidgetDataOutput;

  console.error( 'Formatting item:', item.type );
  let tags: string[] = [];

  if ( item.type === 'card' ){
    const cardItem = item as unknown as CardItem;
    tags = (( await cardItem.getAllTags()) || []).map( tag => tag.title );
  }

  // Extract text content and strip HTML
  const text = formatTextContent( item.data?.content || item.data?.title || '' );
  const description = formatTextContent( item.data?.description || '' );

  // Get color
  const color = ( item as StickyNoteItem )?.style?.fillColor;

  // Determine artifact type. Cards are always Invariants — black-card-as-data-structure
  // is deprecated; data structures now come from SVG code blocks attached via connector.
  let artifactType: string | undefined;
  if ( item.type === 'card' ) {
    artifactType = 'Invariant';
  } else if ( item.type === 'shape' && data?.shape === 'can' ) {
    artifactType = 'Database';
  } else if ( color && getArtifactType( color )) {
    artifactType = getArtifactType( color );
  }

  // Determine actual type (for shapes, use the shape type)
  const type = item.type === 'shape' ? ( data?.shape || 'shape' ) : item.type!;

  return {
    id: item.id,
    type,
    text,
    description,
    color,
    x: Math.round( item.position?.x || 0 ),
    y: Math.round( item.position?.y || 0 ),
    width: Math.round( item.geometry?.width || 0 ),
    height: Math.round( item.geometry?.height || 0 ),
    ...( tags.length > 0 ? { tags } : {}),
    ...( artifactType ? { artifactType } : {})
  };
};

// Check if two bounding boxes overlap
function checkOverlap( item1: PreprocessedItem, item2: PreprocessedItem ): boolean {
  const left1 = item1.x - item1.width / 2;
  const right1 = item1.x + item1.width / 2;
  const top1 = item1.y - item1.height / 2;
  const bottom1 = item1.y + item1.height / 2;

  const left2 = item2.x - item2.width / 2;
  const right2 = item2.x + item2.width / 2;
  const top2 = item2.y - item2.height / 2;
  const bottom2 = item2.y + item2.height / 2;

  return !( right1 < left2 || left1 > right2 || bottom1 < top2 || top1 > bottom2 );
}

// Compute mini-sticky relationships
function computeMiniStickies( items: PreprocessedItem[]): void {
  for ( const item of items ) {
    if ( item.type !== 'sticky_note' ) continue;

    for ( const other of items ) {
      if ( item.id === other.id ) continue;
      if ( other.type !== 'sticky_note' ) continue;
      if ( !other.artifactType ) continue;
      if ( other.artifactType !== 'Aggregate' && other.artifactType !== 'Policy' ) continue;

      if ( checkOverlap( item, other )) {
        const itemArea = item.width * item.height;
        const otherArea = other.width * other.height;

        if ( itemArea < otherArea * 0.5 ) {
          item.isMinSticky = true;
          item.parentOverlap = other.id;
          break;
        }
      }
    }
  }
}

// Detect flow start points (leftmost artifacts on rows containing UI/Command)
function detectFlowStarts( items: PreprocessedItem[]): Array<{ x: number; y: number }> {
  const entryPoints = items.filter( i =>
    i.artifactType === 'UI' || i.artifactType === 'Command' );

  if ( entryPoints.length === 0 ) return [];

  const yPositions: number[] = [];
  for ( const point of entryPoints ) {
    if ( !yPositions.some( y => Math.abs( y - point.y ) <= 20 )) {
      yPositions.push( point.y );
    }
  }

  const flowStarts: Array<{ x: number; y: number }> = [];
  for ( const y of yPositions ) {
    const rowItems = items.filter( i => Math.abs( i.y - y ) <= 20 );
    if ( rowItems.length === 0 ) continue;
    const leftmost = rowItems.reduce(( min, item ) =>
      item.x < min.x ? item : min );
    flowStarts.push({ x: leftmost.x, y: leftmost.y });
  }

  return flowStarts.sort(( a, b ) => a.y - b.y );
}

function validateConnector(
  connector: Connector,
  itemsMap: Map<string, PreprocessedItem>
): { isValid: boolean; validationError?: string; fromType?: string; toType?: string } {
  const startItem = itemsMap.get( connector.startItem?.id! );
  const endItem = itemsMap.get( connector.endItem?.id! );

  if ( !startItem || !endItem ) {
    return { isValid: false, validationError: 'Start or end item not found' };
  }

  const fromType = startItem.artifactType;
  const toType = endItem.artifactType;

  if ( !fromType || !toType ) {
    return { isValid: false, validationError: 'Cannot determine artifact types', fromType, toType };
  }

  const isValid = ALLOWED_EDGES.has( `${fromType}->${toType}` ) || ALLOWED_EDGES.has( `${toType}->${fromType}` );

  return {
    isValid,
    validationError: isValid ? undefined : `Invalid edge pattern between ${fromType} and ${toType}`,
    fromType,
    toType
  };
}

const formatConnector = (
  connector: Connector,
  itemsMap: Map<string, PreprocessedItem>
): PreprocessedConnector => {
  const validation = validateConnector( connector, itemsMap );

  return {
    id: connector.id,
    from: connector.startItem?.id!,
    to: connector.endItem?.id!,
    fromType: validation.fromType,
    toType: validation.toType,
    isValid: validation.isValid,
    validationError: validation.validationError
  };
};

function parseFrameUrl( url: string ): { boardId: string; frameId: string } {
  const boardMatch = url.match( /\/board\/([^/?]+)/ );
  if ( !boardMatch ) {
    throw new Error( 'Invalid Miro board URL - cannot extract board ID' );
  }
  const boardId = boardMatch[1];

  const frameMatch = url.match( /[?&](moveToWidget|focusWidget)=([^&]+)/ );
  if ( !frameMatch ) {
    throw new Error(
      'URL must include moveToWidget or focusWidget parameter to identify the frame'
    );
  }
  const frameId = frameMatch[2];

  return { boardId, frameId };
}

const start = async() => {
  const args = process.argv.slice( 2 );

  if ( args.length === 0 || args.includes( '--help' ) || args.includes( '-h' )) {
    console.log( `
Miro Frame Data Extractor

Retrieves all children (items) from a Miro frame, plus callouts and code blocks
parsed from a manually-exported SVG of the same frame.

Usage:
  npm run frame -- <miro-url-with-frame> --svg <path-to-frame.svg> [--pretty]
  npx tsx get-frame-data.ts <miro-url-with-frame> --svg <path-to-frame.svg> [--pretty]

Arguments:
  miro-url-with-frame    Full Miro URL including moveToWidget or focusWidget parameter
                         Example: https://miro.com/app/board/uXjVJkHBn_k=/?moveToWidget=3458764656081951792

Options:
  --svg <path>          REQUIRED. Path to the frame's SVG export (right-click frame
                        in Miro → Export selection → SVG). Used to extract callouts
                        and code blocks that the Miro API does not expose.
  --pretty              Pretty-print JSON output (default: compact)
  --help, -h            Show this help message

Callout color semantics:
  Red   → hot spot (questions, problems, things to discuss)
  Blue  → info (comments, things to know)
  Green → idea (opportunities, things to explore)

Data structures: provided via SVG code blocks linked by a connector to a sticky.
(Black cards used to play this role; they are deprecated.)

Environment:
  MIRO_ACCESS_TOKEN  Required. Set it as an environment variable (recommended), or in a .env
                     file in the current directory or beside this script. An exported env var
                     always takes precedence over a .env file.
    ` );
    process.exit( 0 );
  }

  const svgFlagIdx = args.indexOf( '--svg' );
  if ( svgFlagIdx === -1 || !args[svgFlagIdx + 1]) {
    console.error( 'Error: --svg <path> is required. Run with --help for details.' );
    process.exit( 1 );
  }
  const svgPath = args[svgFlagIdx + 1];
  if ( !fs.existsSync( svgPath )) {
    console.error( `Error: SVG file not found at ${svgPath}` );
    process.exit( 1 );
  }

  const positional = args.filter(( a, i ) => !a.startsWith( '--' ) && args[i - 1] !== '--svg' );
  const frameUrl = positional[0];
  if ( !frameUrl ) {
    console.error( 'Error: frame URL is required as the first positional argument.' );
    process.exit( 1 );
  }
  const pretty = args.includes( '--pretty' );

  const accessToken = process.env.MIRO_ACCESS_TOKEN;
  if ( !accessToken ) {
    console.error( 'Error: MIRO_ACCESS_TOKEN environment variable is required.' );
    console.error( 'Set MIRO_ACCESS_TOKEN as an environment variable (e.g. `export MIRO_ACCESS_TOKEN=...`), or put it in a .env file in the current directory or beside this script.' );
    process.exit( 1 );
  }

  try {
    const { boardId, frameId } = parseFrameUrl( frameUrl );
    const board = await miro.getBoard( boardId );
    const frame = await board.getFrameItem( frameId );
    const items = frame.getAllItems();
    const itemsMap = new Map<string, PreprocessedItem>();

    console.error( 'Getting items from Miro API...' );
    for await ( let item of items ) {
      if ( item.type === 'sticky_note' ) {
        item = await board.getStickyNoteItem( item.id );
      } else if ( item.type === 'card' ) {
        item = await board.getCardItem( item.id );
      }
      itemsMap.set( item.id, await formatItem( item as Item ) as PreprocessedItem );
    }

    console.error( 'Computing mini-sticky relationships...' );
    computeMiniStickies( Array.from( itemsMap.values()));

    const connectors = board.getAllConnectors();
    const connectorsSet = new Set<PreprocessedConnector>();
    console.error( 'Getting connectors... this will take a while' );
    for await ( const connector of connectors ) {
      console.error( 'Processing connector:', connector.id );
      if ( itemsMap.has( connector.startItem?.id! ) && itemsMap.has( connector.endItem?.id! )) {
        connectorsSet.add( formatConnector( connector as Connector, itemsMap ));
      }
    }

    console.error( `Parsing SVG: ${svgPath}` );
    const { callouts, codeBlocks, connectors: svgConnectors } = parseSvg( svgPath );
    console.error( `SVG found: ${callouts.length} callouts, ${codeBlocks.length} code blocks, ${svgConnectors.length} connectors` );

    const itemsArray = Array.from( itemsMap.values());
    const apiConnectors = Array.from( connectorsSet );

    console.error( 'Attaching code blocks to stickies (matching SVG content to API code items)...' );
    const consumedCodeItemIds = attachCodeBlocks( itemsArray, apiConnectors, codeBlocks );

    console.error( 'Attaching callouts via tail-tip point-in-bbox...' );
    attachCallouts( itemsArray, callouts );

    console.error( 'Filtering out consumed code items and callout body shapes...' );
    const calloutBodyIds = findCalloutBodyShapeIds( itemsArray, callouts );
    const filteredOutIds = new Set([
      ...Array.from( consumedCodeItemIds ),
      ...Array.from( calloutBodyIds )
    ]);
    const filteredItems = itemsArray.filter( item => !filteredOutIds.has( item.id ));
    const filteredConnectors = apiConnectors.filter(
      c => !filteredOutIds.has( c.from ) && !filteredOutIds.has( c.to )
    );

    console.error( 'Detecting flow start points...' );
    const flowStarts = detectFlowStarts( filteredItems );

    const metadata = {
      flowStarts,
      rowThreshold: 20,
      svg: {
        callouts: callouts.length,
        codeBlocks: codeBlocks.length,
        connectors: svgConnectors.length,
        consumedApiCodeItems: consumedCodeItemIds.size,
        consumedApiCalloutBodies: calloutBodyIds.size
      }
    };

    const output = {
      items: filteredItems,
      connectors: filteredConnectors,
      metadata
    };

    console.log( pretty ? JSON.stringify( output, null, 2 ) : JSON.stringify( output ));
  } catch ( error ) {
    console.error( error );
  }
};

start();
