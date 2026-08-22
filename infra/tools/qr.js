// A QR encoder, in one file, with no dependencies.
//
// Why this exists rather than an npm package: the poster generator runs on
// whatever laptop is about to walk into a shop, and the one thing that must
// never happen before a sales call is `npm install` failing on café wifi. The
// repo already needs Node for the Appwrite Functions, so a self-contained
// encoder costs one file and removes an entire class of "it worked at home".
//
// Byte mode only, which covers every URL. Versions 1–40, error-correction
// levels L/M/Q/H. See `test/qr.test.js` — the encoding is checked against the
// Reed-Solomon and BCH algebra rather than against a stored picture, so a
// mistake surfaces as a failed proof instead of an unscannable poster.

// ─── GF(256) ───────────────────────────────────────────────────────────────────
//
// The field QR uses: bytes as polynomials mod the primitive polynomial 0x11D.

const GF_EXP = new Uint8Array(512);
const GF_LOG = new Uint8Array(256);

{
  let x = 1;
  for (let i = 0; i < 255; i++) {
    GF_EXP[i] = x;
    GF_LOG[x] = i;
    x <<= 1;
    if (x & 0x100) x ^= 0x11d;
  }
  // Doubled so a log sum up to 508 can be indexed without a modulo.
  for (let i = 255; i < 512; i++) GF_EXP[i] = GF_EXP[i - 255];
}

export function gfMul(a, b) {
  if (a === 0 || b === 0) return 0;
  return GF_EXP[GF_LOG[a] + GF_LOG[b]];
}

export function gfPow(exponent) {
  return GF_EXP[((exponent % 255) + 255) % 255];
}

// ─── Reed-Solomon ──────────────────────────────────────────────────────────────

/// The generator polynomial ∏(x − α^i) for i in 0..degree-1, highest power
/// first. Its roots are exactly what `test/qr.test.js` evaluates the finished
/// codeword at.
export function rsGenerator(degree) {
  let poly = [1];
  for (let i = 0; i < degree; i++) {
    const next = new Array(poly.length + 1).fill(0);
    for (let j = 0; j < poly.length; j++) {
      next[j] ^= poly[j]; // × x
      next[j + 1] ^= gfMul(poly[j], GF_EXP[i]); // × α^i
    }
    poly = next;
  }
  return poly;
}

/// The `degree` error-correction codewords for `data`.
export function rsRemainder(data, degree) {
  const gen = rsGenerator(degree);
  const result = new Uint8Array(degree);
  for (const byte of data) {
    const factor = byte ^ result[0];
    result.copyWithin(0, 1);
    result[degree - 1] = 0;
    for (let i = 0; i < degree; i++) {
      result[i] ^= gfMul(gen[i + 1], factor);
    }
  }
  return result;
}

// ─── Version capacity ──────────────────────────────────────────────────────────

const ECC_PER_BLOCK = {
  L: [-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 20, 30,
    24, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30],
  M: [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26,
    26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28,
    28, 28, 28],
  Q: [-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28,
    26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30],
  H: [-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28,
    26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30,
    30, 30, 30],
};

const NUM_BLOCKS = {
  L: [-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9,
    10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
  M: [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17,
    17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
  Q: [-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20,
    23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65,
    68],
  H: [-1, 1, 1, 2, 4, 4, 4, 5, 5, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25,
    25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77,
    81],
};

/// Modules available to data and error correction once the finder, timing,
/// alignment, format and version patterns have taken their share.
///
/// Deriving this rather than storing a capacity table means the tables above
/// are cross-checked: `test/qr.test.js` asserts the data capacity that falls
/// out of these two agrees with the standard's published figures.
export function numRawDataModules(version) {
  let result = (16 * version + 128) * version + 64;
  if (version >= 2) {
    const numAlign = Math.floor(version / 7) + 2;
    result -= (25 * numAlign - 10) * numAlign - 55;
    if (version >= 7) result -= 36;
  }
  return result;
}

export function numDataCodewords(version, ecl) {
  return (
    Math.floor(numRawDataModules(version) / 8) -
    ECC_PER_BLOCK[ecl][version] * NUM_BLOCKS[ecl][version]
  );
}

// ─── Bit stream ────────────────────────────────────────────────────────────────

class BitBuffer {
  constructor() {
    this.bits = [];
  }

  append(value, length) {
    for (let i = length - 1; i >= 0; i--) {
      this.bits.push((value >>> i) & 1);
    }
  }
}

/// Byte mode carries an 8-bit length below version 10 and 16 bits at or above
/// it, which is why the version has to be chosen before the header is written.
function charCountBits(version) {
  return version < 10 ? 8 : 16;
}

function smallestVersion(byteLength, ecl, minVersion, maxVersion) {
  for (let version = minVersion; version <= maxVersion; version++) {
    const capacity = numDataCodewords(version, ecl) * 8;
    const used = 4 + charCountBits(version) + byteLength * 8;
    if (used <= capacity) return version;
  }
  return null;
}

function buildCodewords(bytes, version, ecl) {
  const capacityBits = numDataCodewords(version, ecl) * 8;
  const buffer = new BitBuffer();

  buffer.append(0b0100, 4); // byte mode
  buffer.append(bytes.length, charCountBits(version));
  for (const byte of bytes) buffer.append(byte, 8);

  // Terminator, then out to a byte boundary, then the standard filler.
  buffer.append(0, Math.min(4, capacityBits - buffer.bits.length));
  buffer.append(0, (8 - (buffer.bits.length % 8)) % 8);

  const codewords = new Uint8Array(capacityBits / 8);
  for (let i = 0; i < buffer.bits.length; i++) {
    codewords[i >>> 3] |= buffer.bits[i] << (7 - (i & 7));
  }
  for (let i = Math.ceil(buffer.bits.length / 8), pad = 0xec;
       i < codewords.length;
       i++, pad ^= 0xec ^ 0x11) {
    codewords[i] = pad;
  }
  return codewords;
}

/// Splits the data into blocks, appends each block's error correction, and
/// interleaves — so a scuff on the poster damages one codeword in each block
/// rather than destroying a single block outright.
export function interleave(data, version, ecl) {
  const numBlocks = NUM_BLOCKS[ecl][version];
  const eccLen = ECC_PER_BLOCK[ecl][version];
  const totalCodewords = Math.floor(numRawDataModules(version) / 8);
  const numShort = numBlocks - (totalCodewords % numBlocks);
  const shortLen = Math.floor(totalCodewords / numBlocks);

  const blocks = [];
  for (let i = 0, offset = 0; i < numBlocks; i++) {
    const dataLen = shortLen - eccLen + (i < numShort ? 0 : 1);
    const blockData = data.slice(offset, offset + dataLen);
    offset += dataLen;
    blocks.push({ data: blockData, ecc: rsRemainder(blockData, eccLen) });
  }

  const result = new Uint8Array(totalCodewords);
  let at = 0;
  const longestData = shortLen - eccLen + 1;
  for (let i = 0; i < longestData; i++) {
    for (const block of blocks) {
      if (i < block.data.length) result[at++] = block.data[i];
    }
  }
  for (let i = 0; i < eccLen; i++) {
    for (const block of blocks) result[at++] = block.ecc[i];
  }
  return result;
}

// ─── Matrix ────────────────────────────────────────────────────────────────────

const ECL_FORMAT_BITS = { L: 1, M: 0, Q: 3, H: 2 };

/// BCH(15,5)-protected format information, masked with 0x5412 so an all-zero
/// region can never read as a valid format.
export function formatBits(ecl, mask) {
  const data = (ECL_FORMAT_BITS[ecl] << 3) | mask;
  let rem = data;
  for (let i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >>> 9) * 0x537);
  return (((data << 10) | rem) ^ 0x5412) & 0x7fff;
}

/// BCH(18,6)-protected version information, present from version 7 up.
export function versionBits(version) {
  let rem = version;
  for (let i = 0; i < 12; i++) rem = (rem << 1) ^ ((rem >>> 11) * 0x1f25);
  return ((version << 12) | rem) & 0x3ffff;
}

export function alignmentPositions(version) {
  if (version === 1) return [];
  const numAlign = Math.floor(version / 7) + 2;
  const step =
    version === 32
      ? 26
      : Math.ceil((version * 4 + 4) / (numAlign * 2 - 2)) * 2;
  const result = [6];
  for (let pos = version * 4 + 10; result.length < numAlign; pos -= step) {
    result.splice(1, 0, pos);
  }
  return result;
}

export function maskAt(mask, x, y) {
  switch (mask) {
    case 0: return (x + y) % 2 === 0;
    case 1: return y % 2 === 0;
    case 2: return x % 3 === 0;
    case 3: return (x + y) % 3 === 0;
    case 4: return (Math.floor(x / 3) + Math.floor(y / 2)) % 2 === 0;
    case 5: return ((x * y) % 2) + ((x * y) % 3) === 0;
    case 6: return (((x * y) % 2) + ((x * y) % 3)) % 2 === 0;
    case 7: return (((x + y) % 2) + ((x * y) % 3)) % 2 === 0;
    default: throw new Error(`mask ${mask} out of range`);
  }
}

class Matrix {
  constructor(version) {
    this.version = version;
    this.size = version * 4 + 17;
    this.modules = Array.from({ length: this.size }, () =>
      new Array(this.size).fill(false));
    this.isFunction = Array.from({ length: this.size }, () =>
      new Array(this.size).fill(false));
  }

  setFunction(x, y, dark) {
    this.modules[y][x] = dark;
    this.isFunction[y][x] = true;
  }

  drawFinder(centerX, centerY) {
    for (let dy = -4; dy <= 4; dy++) {
      for (let dx = -4; dx <= 4; dx++) {
        const x = centerX + dx;
        const y = centerY + dy;
        if (x < 0 || x >= this.size || y < 0 || y >= this.size) continue;
        const distance = Math.max(Math.abs(dx), Math.abs(dy));
        this.setFunction(x, y, distance !== 2 && distance !== 4);
      }
    }
  }

  drawAlignment(centerX, centerY) {
    for (let dy = -2; dy <= 2; dy++) {
      for (let dx = -2; dx <= 2; dx++) {
        const distance = Math.max(Math.abs(dx), Math.abs(dy));
        this.setFunction(centerX + dx, centerY + dy, distance !== 1);
      }
    }
  }

  drawFunctionPatterns() {
    for (let i = 0; i < this.size; i++) {
      this.setFunction(6, i, i % 2 === 0);
      this.setFunction(i, 6, i % 2 === 0);
    }

    this.drawFinder(3, 3);
    this.drawFinder(this.size - 4, 3);
    this.drawFinder(3, this.size - 4);

    const positions = alignmentPositions(this.version);
    for (let i = 0; i < positions.length; i++) {
      for (let j = 0; j < positions.length; j++) {
        // The three finder corners have no alignment pattern on top of them.
        const skip =
          (i === 0 && j === 0) ||
          (i === 0 && j === positions.length - 1) ||
          (i === positions.length - 1 && j === 0);
        if (!skip) this.drawAlignment(positions[i], positions[j]);
      }
    }

    // Reserved until the mask is chosen; drawn for real by drawFormat().
    this.drawFormat('L', 0);
    if (this.version >= 7) this.drawVersion();
  }

  drawFormat(ecl, mask) {
    const bits = formatBits(ecl, mask);
    const bit = (i) => ((bits >>> i) & 1) !== 0;

    for (let i = 0; i <= 5; i++) this.setFunction(8, i, bit(i));
    this.setFunction(8, 7, bit(6));
    this.setFunction(8, 8, bit(7));
    this.setFunction(7, 8, bit(8));
    for (let i = 9; i < 15; i++) this.setFunction(14 - i, 8, bit(i));

    for (let i = 0; i < 8; i++) {
      this.setFunction(this.size - 1 - i, 8, bit(i));
    }
    for (let i = 8; i < 15; i++) {
      this.setFunction(8, this.size - 15 + i, bit(i));
    }
    this.setFunction(8, this.size - 8, true); // the always-dark module
  }

  drawVersion() {
    const bits = versionBits(this.version);
    for (let i = 0; i < 18; i++) {
      const dark = ((bits >>> i) & 1) !== 0;
      const a = this.size - 11 + (i % 3);
      const b = Math.floor(i / 3);
      this.setFunction(a, b, dark);
      this.setFunction(b, a, dark);
    }
  }

  /// Lays the codewords out in the two-module-wide zigzag that starts at the
  /// bottom right and skips the column occupied by the vertical timing pattern.
  drawCodewords(data) {
    let i = 0;
    for (let right = this.size - 1; right >= 1; right -= 2) {
      if (right === 6) right = 5;
      for (let vert = 0; vert < this.size; vert++) {
        for (let j = 0; j < 2; j++) {
          const x = right - j;
          const upward = ((right + 1) & 2) === 0;
          const y = upward ? this.size - 1 - vert : vert;
          if (!this.isFunction[y][x] && i < data.length * 8) {
            this.modules[y][x] = ((data[i >>> 3] >>> (7 - (i & 7))) & 1) !== 0;
            i++;
          }
        }
      }
    }
  }

  applyMask(mask) {
    for (let y = 0; y < this.size; y++) {
      for (let x = 0; x < this.size; x++) {
        if (!this.isFunction[y][x] && maskAt(mask, x, y)) {
          this.modules[y][x] = !this.modules[y][x];
        }
      }
    }
  }

  /// The standard's four penalty rules. Lower is more likely to scan.
  penalty() {
    const size = this.size;
    const dark = (x, y) => this.modules[y][x];
    let score = 0;

    // Rule 1 — runs of five or more same-coloured modules in a line.
    for (const horizontal of [true, false]) {
      for (let a = 0; a < size; a++) {
        let runColor = null;
        let runLength = 0;
        for (let b = 0; b < size; b++) {
          const color = horizontal ? dark(b, a) : dark(a, b);
          if (color === runColor) {
            runLength++;
            if (runLength === 5) score += 3;
            else if (runLength > 5) score += 1;
          } else {
            runColor = color;
            runLength = 1;
          }
        }
      }
    }

    // Rule 2 — every 2×2 block of one colour.
    for (let y = 0; y < size - 1; y++) {
      for (let x = 0; x < size - 1; x++) {
        const c = dark(x, y);
        if (c === dark(x + 1, y) && c === dark(x, y + 1) &&
            c === dark(x + 1, y + 1)) {
          score += 3;
        }
      }
    }

    // Rule 3 — the finder-lookalike 1:1:3:1:1 pattern with four light modules
    // on either side, which is what makes a scanner mistake data for a corner.
    const pattern = [true, false, true, true, true, false, true];
    const quiet = [false, false, false, false];
    const matches = (line, at, seq) =>
      seq.every((want, k) => line[at + k] === want);

    for (const horizontal of [true, false]) {
      for (let a = 0; a < size; a++) {
        const line = [];
        for (let b = 0; b < size; b++) {
          line.push(horizontal ? dark(b, a) : dark(a, b));
        }
        for (let at = 0; at + 7 <= size; at++) {
          if (!matches(line, at, pattern)) continue;
          const beforeClear =
            at >= 4 && matches(line, at - 4, quiet);
          const afterClear =
            at + 11 <= size && matches(line, at + 7, quiet);
          if (beforeClear || afterClear) score += 40;
        }
      }
    }

    // Rule 4 — deviation from a half-dark symbol.
    let darkCount = 0;
    for (let y = 0; y < size; y++) {
      for (let x = 0; x < size; x++) if (dark(x, y)) darkCount++;
    }
    const total = size * size;
    const percent = (darkCount * 100) / total;
    const k = Math.floor(Math.abs(percent - 50) / 5);
    score += k * 10;

    return score;
  }
}

// ─── Public API ────────────────────────────────────────────────────────────────

/**
 * Encodes `text` as a QR symbol.
 *
 * @param {string} text
 * @param {{ecl?: 'L'|'M'|'Q'|'H', minVersion?: number, maxVersion?: number,
 *          mask?: number}} [options]
 * @returns {{modules: boolean[][], size: number, version: number,
 *            ecl: string, mask: number}}
 */
export function encodeQr(text, options = {}) {
  const ecl = options.ecl ?? 'Q';
  const minVersion = options.minVersion ?? 1;
  const maxVersion = options.maxVersion ?? 40;

  if (!(ecl in ECC_PER_BLOCK)) {
    throw new Error(`unknown error-correction level ${ecl}`);
  }

  const bytes = new TextEncoder().encode(text);
  const version = smallestVersion(bytes.length, ecl, minVersion, maxVersion);
  if (version === null) {
    throw new Error(
      `${bytes.length} bytes do not fit in a version-${maxVersion} ` +
      `symbol at error-correction level ${ecl}`);
  }

  const codewords = interleave(buildCodewords(bytes, version, ecl), version,
    ecl);

  const matrix = new Matrix(version);
  matrix.drawFunctionPatterns();
  matrix.drawCodewords(codewords);

  let bestMask = options.mask ?? -1;
  if (bestMask < 0) {
    let bestPenalty = Infinity;
    for (let mask = 0; mask < 8; mask++) {
      matrix.applyMask(mask);
      matrix.drawFormat(ecl, mask);
      const penalty = matrix.penalty();
      if (penalty < bestPenalty) {
        bestPenalty = penalty;
        bestMask = mask;
      }
      matrix.applyMask(mask); // XOR is its own inverse — undo before the next
    }
  }

  matrix.applyMask(bestMask);
  matrix.drawFormat(ecl, bestMask);

  return {
    modules: matrix.modules,
    size: matrix.size,
    version,
    ecl,
    mask: bestMask,
  };
}

/**
 * Renders an encoded symbol as SVG.
 *
 * One `<path>` of rectangles rather than a grid of `<rect>` elements, which
 * keeps the file small enough to inline into a poster and prints without
 * hairline seams between modules.
 *
 * @param {ReturnType<typeof encodeQr>} qr
 * @param {{scale?: number, margin?: number, dark?: string, light?: string,
 *          id?: string}} [options]
 */
export function qrToSvg(qr, options = {}) {
  const scale = options.scale ?? 4;
  const margin = options.margin ?? 4; // the standard's quiet zone
  const dark = options.dark ?? '#000000';
  const light = options.light ?? '#ffffff';

  const dimension = (qr.size + margin * 2) * scale;
  const parts = [];
  for (let y = 0; y < qr.size; y++) {
    for (let x = 0; x < qr.size; x++) {
      if (qr.modules[y][x]) {
        parts.push(`M${(x + margin) * scale} ${(y + margin) * scale}` +
          `h${scale}v${scale}h-${scale}z`);
      }
    }
  }

  return [
    `<svg xmlns="http://www.w3.org/2000/svg" width="${dimension}" ` +
      `height="${dimension}" viewBox="0 0 ${dimension} ${dimension}" ` +
      `shape-rendering="crispEdges" role="img" ` +
      `aria-label="QR-Code">`,
    `<rect width="${dimension}" height="${dimension}" fill="${light}"/>`,
    `<path fill="${dark}" d="${parts.join('')}"/>`,
    `</svg>`,
  ].join('');
}

/// Convenience: text straight to SVG.
export function qrSvg(text, options = {}) {
  return qrToSvg(encodeQr(text, options), options);
}

/// Which modules a given version reserves for function patterns. Exported so
/// the round-trip test can walk the data modules without re-deriving the
/// layout by hand.
export function functionModuleMap(version) {
  const matrix = new Matrix(version);
  matrix.drawFunctionPatterns();
  return matrix.isFunction;
}

export { ECC_PER_BLOCK, NUM_BLOCKS, charCountBits };
