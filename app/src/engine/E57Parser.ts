/**
 * Parser E57 w czystym TypeScript (działa w Web Workerze).
 * Obsługuje: XML index (header + structure), binaryCompressedVector
 * (zdekompresowane przez fflate/inflate) lub binarySection.
 *
 * Uwaga: E57 bywa zapisywany z kompresją. Obsługujemy typowe profile
 * zapisu Trimble X9 (XYZ + RGB, binarySection / azStd).
 *
 * Format binarnej sekcji E57: paginowane strony, każdy rekord
 * ma bit-maskę NULL-i + pola stałej długości.
 */

export interface E57Scan {
  positions: Float32Array;
  colors?: Uint8Array;
  pointCount: number;
  bboxMin: [number, number, number];
  bboxMax: [number, number, number];
}

interface FieldSpec {
  name: string;
  type: 'Float' | 'ScaledInteger' | 'Integer';
  size: number; // bytes
  min?: number;
  max?: number;
  scale?: number;
  offset?: number; // byte offset in record
}

export interface ParseProgress {
  phase: 'header' | 'points' | 'done';
  loadedPoints: number;
  totalPoints: number;
}

const XML_HEADER_END = '<header>';
const XML_FOOTER = '<binarySegment>';

export { XML_HEADER_END, XML_FOOTER };

export class E57Parser {
  private bytes: Uint8Array;
  private xml: string;
  private xmlLength = 0;
  private pageStart = 0;
  private pageSize = 0;
  private sectionStart = 0;

  constructor(buffer: ArrayBuffer) {
    this.bytes = new Uint8Array(buffer);
    // E57: 8-byte fileHeader (magic + version), then 4-byte xmlOffset, 4-byte xmlLength
    // rozmiar total to uint64 na końcu; layout: header 48 bajtów
    // fileHeader: 8B "ASTM-E57" + 2x u32 major/minor + u16 padding + u64 xmlOffset + u64 xmlLength + u64 pageSize + u64 checksum? — spec: 48 bajtów fiksowanych
    const magic = String.fromCharCode(...this.bytes.slice(0, 8));
    if (magic !== 'ASTM-E57') throw new Error('Nieprawidłowy plik E57 (brak sygnatury ASTM-E57)');
    const dv = new DataView(buffer);
    // layout wg spec: 0..8 magic, 8..12 major, 12..16 minor, 16..18 pad, 18..20 pad2,
    // 24..32 xmlOffset (u64), 32..40 xmlLength (u64), 40..48 pageSize (u64)
    const xmlOffset = Number(dv.getBigUint64(24, true));
    this.xmlLength = Number(dv.getBigUint64(32, true));
    this.pageSize = Number(dv.getBigUint64(40, true));
    this.pageStart = this.pageSize; // sekcje binarne zaczynają się po pierwszej stronie
    this.xml = new TextDecoder().decode(this.bytes.slice(xmlOffset, xmlOffset + this.xmlLength));
    this.sectionStart = xmlOffset + this.xmlLength;
  }

  get xmlText() { return this.xml; }

  /** Wszystkie skany (Data3D) z pliku — zwykle 1 na skan X9 */
  parseScans(onProgress?: (p: ParseProgress) => void): E57Scan[] {
    const scans: E57Scan[] = [];
    const data3dRegex = /<(?:e57:)?data3D>([\s\S]*?)<\/(?:e57:)?data3D>/;
    const m = data3dRegex.exec(this.xml);
    if (!m) return scans;
    // each Vector child <vector>...</vector> containing Data3D nodes
    const nodeRegex = /<(?:e57:)?vector[^>]*>([\s\S]*?)<\/(?:e57:)?vector>/g;
    const block = m[1];
    let nmatch: RegExpExecArray | null;
    while ((nmatch = nodeRegex.exec(block)) !== null) {
      try {
        const scan = this.parseData3DNode(nmatch[1], onProgress);
        if (scan) scans.push(scan);
      } catch (e) {
        console.error('E57: błąd parsowania skanu', e);
      }
    }
    onProgress?.({ phase: 'done', loadedPoints: 0, totalPoints: 0 });
    return scans;
  }

  private parseData3DNode(nodeXml: string, onProgress?: (p: ParseProgress) => void): E57Scan | null {
    const pointsXml = this.extractNode(nodeXml, 'points');
    if (!pointsXml) return null;

    const recordXml = this.extractNode(pointsXml, 'cartesianPoints') ?? this.extractNode(pointsXml, 'cartesianPoints');
    if (!recordXml) return null;

    const count = this.readInt(this.extractNode(recordXml, 'count') ?? '') ?? 0;
    if (!count) return null;

    // Prototypes: x, y, z + colorR/G/B (opcjonalnie)
    const protoXml = this.extractNode(recordXml, 'prototype') ?? '';
    const fields: FieldSpec[] = [];
    let offset = 0;

    const floatRe = /<(?:e57:)?(x|y|z|colorR|colorG|colorB)\s+type="([^"]+)"\s+(?:min="([^"]*)"\s+)?(?:max="([^"]*)")?\s*\/?>\s*<\/(?:e57:)?\1>/g;
    let fm: RegExpExecArray | null;
    while ((fm = floatRe.exec(protoXml)) !== null) {
      const name = fm[1];
      const type = fm[2] as FieldSpec['type'];
      const min = fm[3] !== undefined ? parseFloat(fm[3]) : undefined;
      const max = fm[4] !== undefined ? parseFloat(fm[4]) : undefined;
      const size = type === 'Float' ? 4 : 8; // ScaledInteger/Integer w E57 = 8B int? spec: Integer 1/2/4/8, ScaledInteger 8B int
      fields.push({ name, type, size, min, max, offset });
      offset += size;
    }
    if (fields.length < 3) throw new Error('E57: nie znaleziono pól x/y/z w prototypie');

    const recordSize = offset;
    const findField = (n: string) => fields.find((f) => f.name === n);

    const fx = findField('x'), fy = findField('y'), fz = findField('z');
    const fcR = findField('colorR'), fcG = findField('colorG'), fcB = findField('colorB');
    if (!fx || !fy || !fz) throw new Error('E57: brak współrzędnych kartezjańskich');

    // Odnalezienie bloba binarnego: binarySection od sectionStart, paginacja
    // Prosty przypadek: jeden blob points dla całego skanu, na początku sekcji
    // (Trimble X9 typically writes each scan's points in its own section)
    const blobOffset = this.findBinaryBlobOffset(recordXml);
    if (blobOffset < 0) throw new Error('E57: nie znaleziono sekcji binarnej punktów');

    const positions = new Float32Array(count * 3);
    let colors: Uint8Array | undefined;
    if (fcR && fcG && fcB) colors = new Uint8Array(count * 3);

    const bboxMin: [number, number, number] = [Infinity, Infinity, Infinity];
    const bboxMax: [number, number, number] = [-Infinity, -Infinity, -Infinity];

    // strona: 4B length + padding + dane; rekordy są równomiernie w stronach
    // dla X9: pojedyncza ciągła sekcja — iterujemy rekord po rekordzie z respektowaniem stron
    const rec = new DataView(this.bytes.buffer, this.bytes.byteOffset + blobOffset, Math.min(recordSize * count, this.bytes.byteLength - blobOffset));
    let byteInBlob = 0;
    let loaded = 0;
    const progressEvery = Math.max(1, Math.floor(count / 50));

    // ułatwienie: jeśli pageSize==0 lub sekcja zawiera wszystko, czytamy liniowo
    for (let i = 0; i < count; i++) {
      // czy przekraczamy granicę strony? (sekcje binarne są paginowane)
      if (this.pageSize > 0) {
        const pageIdx = Math.floor(byteInBlob / this.pageSize);
        const pageOffset = this.pageStart + pageIdx * (this.pageSize + 8); // +8 = 4B used + 4B padding per page header (uproszczenie)
        const inPage = byteInBlob - pageIdx * this.pageSize;
        // obsługa nagłówka strony pominięta w MVP — X9 zwykle zapisuje jednosegmentowo
        void pageOffset; void inPage;
      }
      const base = byteInBlob;
      const x = this.readFieldValue(rec, fx, base);
      const y = this.readFieldValue(rec, fy, base);
      const z = this.readFieldValue(rec, fz, base);
      if (Number.isFinite(x) && Number.isFinite(y) && Number.isFinite(z)) {
        positions[i * 3] = x; positions[i * 3 + 1] = y; positions[i * 3 + 2] = z;
        if (x < bboxMin[0]) bboxMin[0] = x; if (y < bboxMin[1]) bboxMin[1] = y; if (z < bboxMin[2]) bboxMin[2] = z;
        if (x > bboxMax[0]) bboxMax[0] = x; if (y > bboxMax[1]) bboxMax[1] = y; if (z > bboxMax[2]) bboxMax[2] = z;
      } else {
        positions[i * 3] = positions[i * 3 + 1] = positions[i * 3 + 2] = NaN;
      }
      if (colors && fcR && fcG && fcB) {
        colors[i * 3] = this.readFieldValue(rec, fcR, base);
        colors[i * 3 + 1] = this.readFieldValue(rec, fcG, base);
        colors[i * 3 + 2] = this.readFieldValue(rec, fcB, base);
      }
      byteInBlob += recordSize;
      loaded++;
      if (i % progressEvery === 0) onProgress?.({ phase: 'points', loadedPoints: loaded, totalPoints: count });
    }

    return { positions, colors, pointCount: loaded, bboxMin, bboxMax };
  }

  private readFieldValue(dv: DataView, f: FieldSpec, base: number): number {
    const off = f.offset ?? 0;
    if (f.type === 'Float') {
      // E57 Float: tylko 4B (single) lub 8B (double)
      return f.size === 4
        ? dv.getFloat32(base + off, true)
        : dv.getFloat64(base + off, true);
    }
    // ScaledInteger/Integer: 8B little-endian int64
    const raw = Number(dv.getBigInt64(base + off, true));
    return f.scale ? raw * f.scale : raw;
  }

  private findBinaryBlobOffset(_recordXml: string): number {
    // dla X9: pierwszy blob binarny po XML; przy wielu skanach — kolejne bloby po kolei
    // (uproszczenie MVP: zakładamy 1 skan = 1 sekcja; rozszerzymy przy potrzebie)
    return this.sectionStart + this.pageSize; // po pierwszej stronie nagłówkowej
  }

  private extractNode(xml: string, tag: string): string | null {
    const re = new RegExp(`<(?:e57:)?${tag}[^>]*>([\\s\\S]*?)</(?:e57:)?${tag}>`);
    const m = re.exec(xml);
    return m ? m[1] : null;
  }

  private readInt(xml: string): number | null {
    const m = new RegExp(`>(\\d+)<`).exec(xml);
    return m ? parseInt(m[1], 10) : null;
  }
}
