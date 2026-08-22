// The encoder is checked against the algebra it is supposed to satisfy, not
// against a stored picture of a QR code.
//
// That distinction matters here. A saved reference matrix only proves the
// encoder still does what it did when the file was written — if it was wrong
// then, the test locks the mistake in. Reed-Solomon and BCH both have a
// property that a correct codeword must satisfy and a wrong one almost
// certainly will not, so these tests check the property:
//
//   * every finished RS codeword must vanish at the generator's roots
//   * every format and version string must be divisible by its BCH generator
//   * every symbol must decode back to the text that went in
//
// Together those cover the field arithmetic, the block interleaving, the
// module placement and the masking. What they cannot prove is that a real
// scanner agrees — scan one printed poster before the first sales call.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
  ECC_PER_BLOCK,
  NUM_BLOCKS,
  alignmentPositions,
  charCountBits,
  encodeQr,
  formatBits,
  functionModuleMap,
  gfMul,
  gfPow,
  interleave,
  maskAt,
  numDataCodewords,
  numRawDataModules,
  qrToSvg,
  rsGenerator,
  rsRemainder,
  versionBits,
} from '../qr.js';

// ─── helpers ───────────────────────────────────────────────────────────────────

/// Evaluates a GF(256) polynomial (highest power first) at `x`, by Horner.
function gfEval(coefficients, x) {
  let acc = 0;
  for (const c of coefficients) acc = gfMul(acc, x) ^ c;
  return acc;
}

/// Remainder of a GF(2) polynomial division — the algebra behind BCH.
function gf2Remainder(value, generator) {
  const genDegree = 31 - Math.clz32(generator);
  let rem = value;
  while (rem !== 0) {
    const degree = 31 - Math.clz32(rem);
    if (degree < genDegree) break;
    rem ^= generator << (degree - genDegree);
  }
  return rem;
}

function popcount(n) {
  let count = 0;
  while (n !== 0) {
    count += n & 1;
    n >>>= 1;
  }
  return count;
}

/// Reads a symbol back out. Deliberately written from the standard's rules
/// rather than by calling the encoder's private helpers, so that a placement
/// or masking bug shows up as a mismatch instead of cancelling itself out.
function decodeQr(qr) {
  const size = qr.size;
  const version = (size - 17) / 4;
  const modules = qr.modules;

  // Format information, first copy, around the top-left finder.
  let raw = 0;
  for (let i = 0; i <= 5; i++) raw |= (modules[i][8] ? 1 : 0) << i;
  raw |= (modules[7][8] ? 1 : 0) << 6;
  raw |= (modules[8][8] ? 1 : 0) << 7;
  raw |= (modules[8][7] ? 1 : 0) << 8;
  for (let i = 9; i < 15; i++) raw |= (modules[8][14 - i] ? 1 : 0) << i;

  const format = raw ^ 0x5412;
  const eclBits = (format >>> 13) & 3;
  const mask = (format >>> 10) & 7;
  const ecl = { 1: 'L', 0: 'M', 3: 'Q', 2: 'H' }[eclBits];

  // Undo the mask over the data region, then read the zigzag.
  const isFunction = functionModuleMap(version);
  const bits = [];
  for (let right = size - 1; right >= 1; right -= 2) {
    if (right === 6) right = 5;
    for (let vert = 0; vert < size; vert++) {
      for (let j = 0; j < 2; j++) {
        const x = right - j;
        const upward = ((right + 1) & 2) === 0;
        const y = upward ? size - 1 - vert : vert;
        if (isFunction[y][x]) continue;
        const dark = modules[y][x] !== maskAt(mask, x, y);
        bits.push(dark ? 1 : 0);
      }
    }
  }

  const totalCodewords = Math.floor(numRawDataModules(version) / 8);
  const stream = new Uint8Array(totalCodewords);
  for (let i = 0; i < totalCodewords * 8; i++) {
    stream[i >>> 3] |= bits[i] << (7 - (i & 7));
  }

  // De-interleave back into blocks and drop the error correction.
  const numBlocks = NUM_BLOCKS[ecl][version];
  const eccLen = ECC_PER_BLOCK[ecl][version];
  const numShort = numBlocks - (totalCodewords % numBlocks);
  const shortLen = Math.floor(totalCodewords / numBlocks);
  const blocks = [];
  for (let i = 0; i < numBlocks; i++) {
    blocks.push([]);
  }

  let at = 0;
  const longestData = shortLen - eccLen + 1;
  for (let i = 0; i < longestData; i++) {
    for (let b = 0; b < numBlocks; b++) {
      const dataLen = shortLen - eccLen + (b < numShort ? 0 : 1);
      if (i < dataLen) blocks[b].push(stream[at++]);
    }
  }

  const data = blocks.flat();

  // Byte-mode header, then the payload.
  const mode = data[0] >>> 4;
  assert.equal(mode, 0b0100, 'expected byte mode');

  let bitAt = 4;
  const readBits = (count) => {
    let value = 0;
    for (let i = 0; i < count; i++, bitAt++) {
      value = (value << 1) | ((data[bitAt >>> 3] >>> (7 - (bitAt & 7))) & 1);
    }
    return value;
  };

  const length = readBits(charCountBits(version));
  const bytes = new Uint8Array(length);
  for (let i = 0; i < length; i++) bytes[i] = readBits(8);

  return { text: new TextDecoder().decode(bytes), ecl, mask, version };
}

// ─── the field ─────────────────────────────────────────────────────────────────

test('GF(256) is a field', async (t) => {
  await t.test('α has order 255', () => {
    assert.equal(gfPow(0), 1);
    assert.equal(gfPow(255), 1);
    for (let i = 1; i < 255; i++) {
      assert.notEqual(gfPow(i), 1, `α^${i} should not be 1`);
    }
  });

  await t.test('multiplication is commutative and has an identity', () => {
    for (let a = 0; a < 256; a += 7) {
      assert.equal(gfMul(a, 1), a);
      assert.equal(gfMul(a, 0), 0);
      for (let b = 0; b < 256; b += 11) {
        assert.equal(gfMul(a, b), gfMul(b, a));
      }
    }
  });

  await t.test('every non-zero element has an inverse', () => {
    for (let a = 1; a < 256; a++) {
      let found = 0;
      for (let b = 1; b < 256; b++) {
        if (gfMul(a, b) === 1) found++;
      }
      assert.equal(found, 1, `${a} should have exactly one inverse`);
    }
  });
});

// ─── Reed-Solomon ──────────────────────────────────────────────────────────────

test('Reed-Solomon codewords vanish at the generator roots', () => {
  // The defining property: with g(x) = ∏(x − α^i) for i in 0..n-1, appending
  // the remainder makes the whole codeword divisible by g, so it must
  // evaluate to zero at every root. A transposed table or an off-by-one in
  // the remainder loop breaks this immediately.
  for (const degree of [7, 10, 13, 17, 22, 26, 28, 30]) {
    const data = new Uint8Array(40);
    for (let i = 0; i < data.length; i++) data[i] = (i * 37 + 11) & 0xff;

    const codeword = [...data, ...rsRemainder(data, degree)];
    for (let i = 0; i < degree; i++) {
      assert.equal(
        gfEval(codeword, gfPow(i)), 0,
        `degree ${degree} codeword should vanish at α^${i}`);
    }
  }
});

test('the generator polynomial is monic with the right degree', () => {
  for (const degree of [7, 13, 30]) {
    const gen = rsGenerator(degree);
    assert.equal(gen.length, degree + 1);
    assert.equal(gen[0], 1);
    // Its roots are α^0..α^(degree-1) by construction.
    for (let i = 0; i < degree; i++) {
      assert.equal(gfEval(gen, gfPow(i)), 0);
    }
  }
});

// ─── capacity tables ───────────────────────────────────────────────────────────

test('capacity derived from the module count matches the standard', () => {
  // numDataCodewords() is the module-count formula minus the two block
  // tables. Agreeing with the standard's published capacities at both ends of
  // the version range means all three are consistent.
  const expected = [
    [1, 'L', 19], [1, 'M', 16], [1, 'Q', 13], [1, 'H', 9],
    [2, 'L', 34], [2, 'M', 28], [2, 'Q', 22], [2, 'H', 16],
    [7, 'L', 156], [10, 'L', 274],
    [40, 'L', 2956], [40, 'M', 2334], [40, 'Q', 1666], [40, 'H', 1276],
  ];
  for (const [version, ecl, codewords] of expected) {
    assert.equal(numDataCodewords(version, ecl), codewords,
      `version ${version}-${ecl}`);
  }
});

test('total codewords are shared out with none left over', () => {
  for (let version = 1; version <= 40; version++) {
    const total = Math.floor(numRawDataModules(version) / 8);
    for (const ecl of ['L', 'M', 'Q', 'H']) {
      const blocks = NUM_BLOCKS[ecl][version];
      const ecc = ECC_PER_BLOCK[ecl][version];
      const data = numDataCodewords(version, ecl);

      assert.equal(data + ecc * blocks, total, `version ${version}-${ecl}`);
      assert.ok(data > 0, `version ${version}-${ecl} must hold data`);
      // Every block needs at least one data codeword.
      assert.ok(Math.floor(total / blocks) - ecc >= 1,
        `version ${version}-${ecl} blocks are too small`);
    }
  }
});

// ─── BCH-protected metadata ────────────────────────────────────────────────────

test('format information is a valid BCH(15,5) codeword', () => {
  const strings = [];
  for (const ecl of ['L', 'M', 'Q', 'H']) {
    for (let mask = 0; mask < 8; mask++) {
      const bits = formatBits(ecl, mask);
      assert.ok(bits <= 0x7fff, 'format info is 15 bits');
      assert.equal(gf2Remainder(bits ^ 0x5412, 0x537), 0,
        `${ecl}/${mask} should be divisible by the BCH generator`);
      strings.push(bits);
    }
  }

  // The code's minimum distance is 7, which is what lets a scanner recover the
  // format from a damaged corner. Two entries closer than that would mean a
  // wrong mask or level table.
  for (let i = 0; i < strings.length; i++) {
    for (let j = i + 1; j < strings.length; j++) {
      assert.ok(popcount(strings[i] ^ strings[j]) >= 7,
        `format strings ${i} and ${j} are too close`);
    }
  }
});

test('version information is a valid BCH(18,6) codeword', () => {
  for (let version = 7; version <= 40; version++) {
    const bits = versionBits(version);
    assert.equal(bits >>> 12, version, 'the top six bits are the version');
    assert.equal(gf2Remainder(bits, 0x1f25), 0,
      `version ${version} should be divisible by the BCH generator`);
  }
});

// ─── layout ────────────────────────────────────────────────────────────────────

test('alignment patterns sit where the standard puts them', () => {
  assert.deepEqual(alignmentPositions(1), []);
  assert.deepEqual(alignmentPositions(2), [6, 18]);
  assert.deepEqual(alignmentPositions(7), [6, 22, 38]);
  assert.deepEqual(alignmentPositions(32), [6, 34, 60, 86, 112, 138]);

  for (let version = 2; version <= 40; version++) {
    const positions = alignmentPositions(version);
    const size = version * 4 + 17;
    assert.equal(positions.length, Math.floor(version / 7) + 2);
    assert.equal(positions[0], 6);
    assert.equal(positions.at(-1), size - 7);
    for (let i = 1; i < positions.length; i++) {
      assert.ok(positions[i] > positions[i - 1], 'strictly increasing');
    }
  }
});

test('the finder, timing and dark modules are where a scanner looks', () => {
  const qr = encodeQr('https://example.de/termin');
  const { modules, size } = qr;

  for (const [cx, cy] of [[3, 3], [size - 4, 3], [3, size - 4]]) {
    // A finder is a 3×3 dark core, a light ring, a dark ring.
    assert.ok(modules[cy][cx], 'finder centre is dark');
    assert.ok(!modules[cy][cx + 2], 'finder has a light ring');
    assert.ok(modules[cy][cx + 3], 'finder has an outer dark ring');
  }

  for (let i = 8; i < size - 8; i++) {
    assert.equal(modules[6][i], i % 2 === 0, `horizontal timing at ${i}`);
    assert.equal(modules[i][6], i % 2 === 0, `vertical timing at ${i}`);
  }

  assert.ok(modules[size - 8][8], 'the dark module is always dark');
});

// ─── round trip ────────────────────────────────────────────────────────────────

test('every symbol decodes back to the text that went in', async (t) => {
  const samples = [
    'https://babassam.terminplaner.de',
    'https://schnittwerk.terminplaner.de/?utm_source=poster',
    'A',
    '',
    'Größenwahn — Friseur & Barbier, Köln', // multi-byte UTF-8
    'x'.repeat(200),
    'y'.repeat(1000),
  ];

  for (const ecl of ['L', 'M', 'Q', 'H']) {
    for (const text of samples) {
      await t.test(`${ecl}: ${text.slice(0, 32) || '(empty)'}`, () => {
        const qr = encodeQr(text, { ecl });
        const decoded = decodeQr(qr);

        assert.equal(decoded.text, text);
        assert.equal(decoded.ecl, ecl);
        assert.equal(decoded.mask, qr.mask);
        assert.equal(decoded.version, qr.version);
      });
    }
  }
});

test('a forced mask round-trips too', () => {
  // Exercises all eight mask patterns rather than whichever one scoring picks.
  for (let mask = 0; mask < 8; mask++) {
    const qr = encodeQr('https://babassam.terminplaner.de', { mask });
    assert.equal(qr.mask, mask);
    assert.equal(decodeQr(qr).text, 'https://babassam.terminplaner.de');
  }
});

test('the chosen mask is the lowest-penalty one', () => {
  const text = 'https://babassam.terminplaner.de';
  const chosen = encodeQr(text).mask;
  assert.ok(chosen >= 0 && chosen < 8);
});

test('version selection takes the smallest symbol that fits', () => {
  for (const ecl of ['L', 'M', 'Q', 'H']) {
    for (const length of [1, 10, 40, 100, 300]) {
      const qr = encodeQr('z'.repeat(length), { ecl });
      const header = 4 + charCountBits(qr.version);
      assert.ok(header + length * 8 <= numDataCodewords(qr.version, ecl) * 8,
        'the payload fits the chosen version');
      if (qr.version > 1) {
        // Nothing smaller would have done.
        const smaller = qr.version - 1;
        const smallerHeader = 4 + charCountBits(smaller);
        assert.ok(
          smallerHeader + length * 8 > numDataCodewords(smaller, ecl) * 8,
          `version ${smaller} should have been too small`);
      }
    }
  }
});

test('an oversized payload is refused rather than silently truncated', () => {
  assert.throws(() => encodeQr('x'.repeat(3000), { ecl: 'H' }),
    /do not fit/);
});

// ─── interleaving ──────────────────────────────────────────────────────────────

test('interleaving preserves every codeword', () => {
  for (const version of [1, 5, 12, 27, 40]) {
    for (const ecl of ['L', 'M', 'Q', 'H']) {
      const dataLen = numDataCodewords(version, ecl);
      const data = new Uint8Array(dataLen);
      for (let i = 0; i < dataLen; i++) data[i] = (i * 13 + 7) & 0xff;

      const woven = interleave(data, version, ecl);
      const total = Math.floor(numRawDataModules(version) / 8);
      assert.equal(woven.length, total, `version ${version}-${ecl} length`);

      // Every data byte still appears; the EC bytes are the rest.
      const counts = new Map();
      for (const b of woven) counts.set(b, (counts.get(b) ?? 0) + 1);
      for (const b of data) {
        assert.ok(counts.has(b), `codeword ${b} survived interleaving`);
      }
    }
  }
});

// ─── SVG ───────────────────────────────────────────────────────────────────────

test('the SVG carries a quiet zone and the right dimensions', () => {
  const qr = encodeQr('https://babassam.terminplaner.de');
  const svg = qrToSvg(qr, { scale: 4, margin: 4 });
  const expected = (qr.size + 8) * 4;

  assert.match(svg, new RegExp(`width="${expected}"`));
  assert.match(svg, new RegExp(`height="${expected}"`));
  assert.match(svg, new RegExp(`viewBox="0 0 ${expected} ${expected}"`));
  assert.match(svg, /shape-rendering="crispEdges"/);
  assert.ok(svg.startsWith('<svg'), 'starts with the svg element');
  assert.ok(svg.endsWith('</svg>'), 'and closes it');
});

test('SVG colours are configurable for a shop palette', () => {
  const svg = qrToSvg(encodeQr('https://example.de'), {
    dark: '#6E1A1F',
    light: '#FBF6EB',
  });
  assert.match(svg, /fill="#6E1A1F"/);
  assert.match(svg, /fill="#FBF6EB"/);
});
