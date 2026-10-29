/**
 * 电路画板 - 数据模型定义
 * 元件 / 导线 / 标注（画笔 & 文本）/ 分析记录 / 画板
 */

/** 点 */
export interface Point {
  x: number;
  y: number;
}

/** 尺寸 */
export interface Size {
  w: number;
  h: number;
}

/** 元件种类（字符串常量，便于 JSON 序列化） */
export class Kinds {
  static readonly BATTERY: string = 'battery';    // 电源
  static readonly RESISTOR: string = 'resistor';  // 电阻
  static readonly CAPACITOR: string = 'capacitor';// 电容
  static readonly INDUCTOR: string = 'inductor';  // 电感
  static readonly SWITCH: string = 'switch';      // 开关
  static readonly BULB: string = 'bulb';          // 灯泡
  static readonly AMMETER: string = 'ammeter';    // 电流表
  static readonly VOLTMETER: string = 'voltmeter';// 电压表
  static readonly GROUND: string = 'ground';      // 接地
}

/** 编辑模式 */
export class Mode {
  static readonly SELECT: string = 'select'; // 选择/移动
  static readonly WIRE: string = 'wire';     // 连线
  static readonly PEN: string = 'pen';       // 画笔标注
  static readonly TEXT: string = 'text';     // 文本标注
  static readonly ERASER: string = 'eraser'; // 橡皮擦
}

/** 元件库条目（左侧面板展示用） */
export interface KindMeta {
  kind: string;
  name: string;
  labelPrefix: string;
  defaultValue: string;
}

export const KIND_LIST: KindMeta[] = [
  { kind: Kinds.BATTERY, name: '电源', labelPrefix: 'E', defaultValue: '12V' },
  { kind: Kinds.RESISTOR, name: '电阻', labelPrefix: 'R', defaultValue: '10Ω' },
  { kind: Kinds.CAPACITOR, name: '电容', labelPrefix: 'C', defaultValue: '100µF' },
  { kind: Kinds.INDUCTOR, name: '电感', labelPrefix: 'L', defaultValue: '10mH' },
  { kind: Kinds.SWITCH, name: '开关', labelPrefix: 'S', defaultValue: '断开' },
  { kind: Kinds.BULB, name: '灯泡', labelPrefix: 'H', defaultValue: '6V' },
  { kind: Kinds.AMMETER, name: '电流表', labelPrefix: 'A', defaultValue: '-' },
  { kind: Kinds.VOLTMETER, name: '电压表', labelPrefix: 'V', defaultValue: '-' },
  { kind: Kinds.GROUND, name: '接地', labelPrefix: 'GND', defaultValue: '' }
];

export function kindMeta(kind: string): KindMeta {
  for (let i = 0; i < KIND_LIST.length; i++) {
    if (KIND_LIST[i].kind === kind) {
      return KIND_LIST[i];
    }
  }
  return KIND_LIST[1];
}

/** 电路元件 */
@ObservedV2
export class CircuitComponent {
  @Trace id: string = '';
  @Trace kind: string = Kinds.RESISTOR;
  @Trace x: number = 0;       // 中心点（画布坐标）
  @Trace y: number = 0;
  @Trace rotation: number = 0; // 0/90/180/270
  @Trace label: string = '';
  @Trace value: string = '';   // 参数：阻值/电压/容值等（手动填写）

  /** 本地坐标系下的引脚偏移（未旋转） */
  pinLocals(): Point[] {
    if (this.kind === Kinds.GROUND) {
      const p: Point = { x: 0, y: -20 };
      return [p];
    }
    const a: Point = { x: -20, y: 0 };
    const b: Point = { x: 20, y: 0 };
    return [a, b];
  }

  pinCount(): number {
    return this.pinLocals().length;
  }

  /** 引脚在画布中的世界坐标 */
  pinWorld(pinIndex: number): Point {
    const locals: Point[] = this.pinLocals();
    const local: Point = pinIndex >= 0 && pinIndex < locals.length ? locals[pinIndex] : locals[0];
    return rotatePoint(local.x, local.y, this.rotation, this.x, this.y);
  }

  /** 未旋转时包围盒（元件本体） */
  bodySize(): Size {
    if (this.kind === Kinds.BATTERY || this.kind === Kinds.CAPACITOR
      || this.kind === Kinds.INDUCTOR || this.kind === Kinds.RESISTOR) {
      const s: Size = { w: 52, h: 30 };
      return s;
    }
    const s2: Size = { w: 48, h: 48 };
    return s2;
  }

  /** 点（世界坐标）是否在元件本体上 */
  contains(wx: number, wy: number): boolean {
    const size: Size = this.bodySize();
    const local: Point = rotatePoint(wx - this.x, wy - this.y, -this.rotation, 0, 0);
    return Math.abs(local.x) <= size.w / 2 && Math.abs(local.y) <= size.h / 2;
  }
}

/** 导线：连接两个引脚；末端允许悬空（toId 为空时用 endX/endY） */
@ObservedV2
export class Wire {
  @Trace id: string = '';
  @Trace fromId: string = '';
  @Trace fromPin: number = 0;
  @Trace toId: string = '';
  @Trace toPin: number = -1;
  @Trace endX: number = 0; // 悬空末端坐标
  @Trace endY: number = 0;
  @Trace bends: Point[] = []; // 中间拐点

  /** 起点世界坐标 */
  start(board: CircuitBoard): Point {
    const comp: CircuitComponent | undefined = board.findComponent(this.fromId);
    if (comp !== undefined) {
      return comp.pinWorld(this.fromPin);
    }
    const p: Point = { x: 0, y: 0 };
    return p;
  }

  /** 终点世界坐标（悬空时为 endX/endY） */
  end(board: CircuitBoard): Point {
    if (this.toId !== '') {
      const comp: CircuitComponent | undefined = board.findComponent(this.toId);
      if (comp !== undefined) {
        return comp.pinWorld(this.toPin);
      }
    }
    const p2: Point = { x: this.endX, y: this.endY };
    return p2;
  }

  /** 完整折线（含拐点） */
  polyline(board: CircuitBoard): Point[] {
    const pts: Point[] = [];
    pts.push(this.start(board));
    for (let i = 0; i < this.bends.length; i++) {
      pts.push(this.bends[i]);
    }
    pts.push(this.end(board));
    return pts;
  }
}

/** 画笔标注（自由手绘） */
@ObservedV2
export class StrokeNote {
  @Trace id: string = '';
  @Trace color: string = '#E53935';
  @Trace width: number = 3;
  @Trace points: Point[] = [];
}

/** 文本标注 */
@ObservedV2
export class TextNote {
  @Trace id: string = '';
  @Trace x: number = 0;
  @Trace y: number = 0; // 文字基线
  @Trace text: string = '';
  @Trace color: string = '#C62828';
  @Trace size: number = 16;

  /** 近似包围盒（用于命中测试） */
  bounds(): Point {
    const p: Point = { x: this.x + this.text.length * this.size, y: this.y - this.size };
    return p;
  }
}

/** 分析记录（学生手动填写） */
@ObservedV2
export class AnalysisRecord {
  @Trace id: string = '';
  @Trace title: string = '';
  @Trace content: string = '';
  @Trace timestamp: number = 0;
}

/** 画板（聚合数据，用于持久化与整体替换） */
@ObservedV2
export class CircuitBoard {
  @Trace name: string = '电路画板 1';
  @Trace components: CircuitComponent[] = [];
  @Trace wires: Wire[] = [];
  @Trace strokes: StrokeNote[] = [];
  @Trace texts: TextNote[] = [];
  @Trace records: AnalysisRecord[] = [];

  findComponent(id: string): CircuitComponent | undefined {
    for (let i = 0; i < this.components.length; i++) {
      if (this.components[i].id === id) {
        return this.components[i];
      }
    }
    return undefined;
  }
}

/** 点绕中心旋转 */
export function rotatePoint(dx: number, dy: number, rotationDeg: number, cx: number, cy: number): Point {
  let rad: number = rotationDeg * Math.PI / 180;
  const cos: number = Math.cos(rad);
  const sin: number = Math.sin(rad);
  const p: Point = { x: cx + dx * cos - dy * sin, y: cy + dx * sin + dy * cos };
  return p;
}

/* ---------------- JSON 反序列化 ---------------- */

interface IPointData {
  x?: number;
  y?: number;
}

interface IComponentData {
  id?: string;
  kind?: string;
  x?: number;
  y?: number;
  rotation?: number;
  label?: string;
  value?: string;
}

interface IWireData {
  id?: string;
  fromId?: string;
  fromPin?: number;
  toId?: string;
  toPin?: number;
  endX?: number;
  endY?: number;
  bends?: IPointData[];
}

interface IStrokeData {
  id?: string;
  color?: string;
  width?: number;
  points?: IPointData[];
}

interface ITextData {
  id?: string;
  x?: number;
  y?: number;
  text?: string;
  color?: string;
  size?: number;
}

interface IRecordData {
  id?: string;
  title?: string;
  content?: string;
  timestamp?: number;
}

interface IBoardData {
  name?: string;
  components?: IComponentData[];
  wires?: IWireData[];
  strokes?: IStrokeData[];
  texts?: ITextData[];
  records?: IRecordData[];
}

function toPoints(list?: IPointData[]): Point[] {
  const pts: Point[] = [];
  if (list !== undefined && list !== null) {
    for (let i = 0; i < list.length; i++) {
      const p: Point = { x: list[i].x ?? 0, y: list[i].y ?? 0 };
      pts.push(p);
    }
  }
  return pts;
}

export function reviveBoard(text: string): CircuitBoard {
  const board: CircuitBoard = new CircuitBoard();
  try {
    const data = JSON.parse(text) as IBoardData;
    board.name = data.name ?? board.name;
    const comps: IComponentData[] = data.components ?? [];
    for (let i = 0; i < comps.length; i++) {
      const c: CircuitComponent = new CircuitComponent();
      c.id = comps[i].id ?? '';
      c.kind = comps[i].kind ?? Kinds.RESISTOR;
      c.x = comps[i].x ?? 0;
      c.y = comps[i].y ?? 0;
      c.rotation = comps[i].rotation ?? 0;
      c.label = comps[i].label ?? '';
      c.value = comps[i].value ?? '';
      board.components.push(c);
    }
    const wires: IWireData[] = data.wires ?? [];
    for (let i = 0; i < wires.length; i++) {
      const w: Wire = new Wire();
      w.id = wires[i].id ?? '';
      w.fromId = wires[i].fromId ?? '';
      w.fromPin = wires[i].fromPin ?? 0;
      w.toId = wires[i].toId ?? '';
      w.toPin = wires[i].toPin ?? -1;
      w.endX = wires[i].endX ?? 0;
      w.endY = wires[i].endY ?? 0;
      w.bends = toPoints(wires[i].bends);
      board.wires.push(w);
    }
    const strokes: IStrokeData[] = data.strokes ?? [];
    for (let i = 0; i < strokes.length; i++) {
      const s: StrokeNote = new StrokeNote();
      s.id = strokes[i].id ?? '';
      s.color = strokes[i].color ?? '#E53935';
      s.width = strokes[i].width ?? 3;
      s.points = toPoints(strokes[i].points);
      board.strokes.push(s);
    }
    const texts: ITextData[] = data.texts ?? [];
    for (let i = 0; i < texts.length; i++) {
      const t: TextNote = new TextNote();
      t.id = texts[i].id ?? '';
      t.x = texts[i].x ?? 0;
      t.y = texts[i].y ?? 0;
      t.text = texts[i].text ?? '';
      t.color = texts[i].color ?? '#C62828';
      t.size = texts[i].size ?? 16;
      board.texts.push(t);
    }
    const records: IRecordData[] = data.records ?? [];
    for (let i = 0; i < records.length; i++) {
      const r: AnalysisRecord = new AnalysisRecord();
      r.id = records[i].id ?? '';
      r.title = records[i].title ?? '';
      r.content = records[i].content ?? '';
      r.timestamp = records[i].timestamp ?? 0;
      board.records.push(r);
    }
  } catch (err) {
    // 解析失败时返回空画板
  }
  return board;
}
