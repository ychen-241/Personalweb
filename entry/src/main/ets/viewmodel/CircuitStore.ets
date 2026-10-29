/**
 * 电路画板 - 状态管理（操作、连线、标注、撤销/重做、持久化）
 */
import {
  AnalysisRecord, CircuitBoard, CircuitComponent, Kinds, kindMeta, Point,
  reviveBoard, StrokeNote, TextNote, Wire, Mode
} from '../model/CircuitTypes';
import { GeometryUtil } from '../common/GeometryUtil';
import { BoardStorage } from '../common/BoardStorage';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const SNAPSHOT_LIMIT: number = 50;

/** 引脚引用 */
export interface PinRef {
  compId: string;
  pinIndex: number;
}

/** 撤销快照（与画板 JSON 结构一致） */
interface BoardSnapshot {
  name: string;
  components: CircuitComponent[];
  wires: Wire[];
  strokes: StrokeNote[];
  texts: TextNote[];
}

@ObservedV2
export class CircuitStore extends CircuitBoard {
  /** 界面状态 */
  @Trace mode: string = Mode.SELECT;
  @Trace selectedId: string = '';
  @Trace statusText: string = '就绪：从左侧添加元件，切换到连线模式用鼠标把引脚连起来';
  @Trace annotationColor: string = '#E53935';
  @Trace undoDepth: number = 0;
  @Trace redoDepth: number = 0;
  @Trace hoverCompId: string = '';
  @Trace hoverPinIndex: number = -1;

  /** 连线草稿 */
  @Trace wireFromId: string = '';
  @Trace wireFromPin: number = -1;
  @Trace wireBends: Point[] = [];

  /** 画布尺寸（由画板视图更新） */
  private canvasW: number = 0;
  private canvasH: number = 0;

  /** 画布重绘回调（画板视图注册） */
  private redrawer: (() => void) | null = null;

  private idSeq: number = 0;
  private placeSeq: number = 0;
  private labelSeq: Record<string, number> = {};
  private undoStack: string[] = [];
  private redoStack: string[] = [];

  /* ---------- 基础 ---------- */

  setRedrawer(fn: (() => void) | null): void {
    this.redrawer = fn;
  }

  touch(): void {
    if (this.redrawer !== null) {
      this.redrawer();
    }
  }

  setCanvasSize(w: number, h: number): void {
    this.canvasW = w;
    this.canvasH = h;
    this.touch();
  }

  canvasCenter(): Point {
    const p: Point = { x: this.canvasW / 2, y: this.canvasH / 2 };
    return p;
  }

  hasCanvas(): boolean {
    return this.canvasW > 0 && this.canvasH > 0;
  }

  genId(prefix: string): string {
    this.idSeq++;
    return `${prefix}_${Date.now()}_${this.idSeq}`;
  }

  nextLabel(kind: string): string {
    const meta = kindMeta(kind);
    const cur: number = this.labelSeq[kind] ?? 0;
    this.labelSeq[kind] = cur + 1;
    return `${meta.labelPrefix}${cur + 1}`;
  }

  setStatus(text: string): void {
    this.statusText = text;
  }

  /* ---------- 撤销 / 重做 ---------- */

  private snapshot(): string {
    const snap: BoardSnapshot = {
      name: this.name,
      components: this.components,
      wires: this.wires,
      strokes: this.strokes,
      texts: this.texts
    };
    return JSON.stringify(snap);
  }

  private applySnapshot(text: string): void {
    const board: CircuitBoard = reviveBoard(text);
    this.name = board.name;
    this.components = board.components;
    this.wires = board.wires;
    this.strokes = board.strokes;
    this.texts = board.texts;
    this.selectedId = '';
    this.cancelWire();
    hilog.info(0xC001, 'CircuitStore',
      `applySnapshot comps=${this.components.length} wires=${this.wires.length}`);
  }

  pushUndo(): void {
    this.undoStack.push(this.snapshot());
    if (this.undoStack.length > SNAPSHOT_LIMIT) {
      this.undoStack.shift();
    }
    this.redoStack = [];
    this.undoDepth = this.undoStack.length;
    this.redoDepth = 0;
  }

  undo(): void {
    if (this.undoStack.length === 0) {
      return;
    }
    this.redoStack.push(this.snapshot());
    const last: string = this.undoStack.pop() as string;
    this.applySnapshot(last);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
    this.setStatus('已撤销');
    this.touch();
  }

  redo(): void {
    if (this.redoStack.length === 0) {
      return;
    }
    this.undoStack.push(this.snapshot());
    const next: string = this.redoStack.pop() as string;
    this.applySnapshot(next);
    this.undoDepth = this.undoStack.length;
    this.redoDepth = this.redoStack.length;
    this.setStatus('已重做');
    this.touch();
  }

  /* ---------- 模式 ---------- */

  setMode(mode: string): void {
    this.mode = mode;
    this.cancelWire();
    this.hoverCompId = '';
    this.hoverPinIndex = -1;
    const tips: Record<string, string> = {};
    tips[Mode.SELECT] = '选择模式：点击选中，拖动移动元件，Delete 删除';
    tips[Mode.WIRE] = '连线模式：点击引脚开始，点击空白加拐点，右键结束（悬空），Esc 取消';
    tips[Mode.PEN] = '画笔标注：按住鼠标在大屏上圈画重点';
    tips[Mode.TEXT] = '文本标注：点击画板位置输入说明文字';
    tips[Mode.ERASER] = '橡皮擦：点击删除导线/标注/元件';
    this.setStatus(tips[mode] ?? '就绪');
    this.touch();
  }

  /* ---------- 元件 ---------- */

  /** 螺旋扫描找一个不与现有元件重叠的空位（避免元件叠在一起） */
  private findFreeSpot(): Point {
    if (!this.hasCanvas()) {
      const p0: Point = { x: 100, y: 100 };
      return p0;
    }
    const center: Point = this.canvasCenter();
    const cellX: number = 100;
    const cellY: number = 90;
    for (let ring = 0; ring < 8; ring++) {
      for (let dx = -ring; dx <= ring; dx++) {
        for (let dy = -ring; dy <= ring; dy++) {
          if (Math.max(Math.abs(dx), Math.abs(dy)) !== ring) {
            continue; // 只检查当前环的边缘
          }
          const cx: number = GeometryUtil.snap(center.x + dx * cellX);
          const cy: number = GeometryUtil.snap(center.y + dy * cellY);
          if (this.isSpotFree(cx, cy)) {
            const p: Point = { x: cx, y: cy };
            return p;
          }
        }
      }
    }
    // 找不到空位时退回级联偏移
    const fx: Point = { x: GeometryUtil.snap(center.x + (this.placeSeq % 8) * 40), y: GeometryUtil.snap(center.y) };
    return fx;
  }

  private isSpotFree(cx: number, cy: number): boolean {
    for (let i = 0; i < this.components.length; i++) {
      const c: CircuitComponent = this.components[i];
      if (Math.abs(c.x - cx) < 90 && Math.abs(c.y - cy) < 80) {
        return false;
      }
    }
    return true;
  }

  addComponent(kind: string): void {
    if (!this.hasCanvas()) {
      this.setStatus('画板尚未就绪，请稍候');
      return;
    }
    this.pushUndo();
    this.placeSeq++;
    const spot: Point = this.findFreeSpot();
    const comp: CircuitComponent = new CircuitComponent();
    comp.id = this.genId('comp');
    comp.kind = kind;
    comp.x = spot.x;
    comp.y = spot.y;
    comp.label = this.nextLabel(kind);
    comp.value = kindMeta(kind).defaultValue;
    this.components.push(comp);
    this.selectedId = comp.id;
    this.setStatus(`已添加 ${kindMeta(kind).name} ${comp.label}，可拖动摆放，或用方向键微调`);
    this.touch();
  }

  /** 方向键 / 按钮移动选中元件（步长=网格 20） */
  moveSelected(dx: number, dy: number): void {
    const comp: CircuitComponent | undefined = this.findComponent(this.selectedId);
    if (comp === undefined) {
      return;
    }
    comp.x = Math.max(30, Math.min(this.canvasW - 30, comp.x + dx));
    comp.y = Math.max(30, Math.min(this.canvasH - 30, comp.y + dy));
    this.touch();
  }

  /** 双击开关：切换闭合/断开 */
  toggleSelectedSwitch(): boolean {
    const comp: CircuitComponent | undefined = this.findComponent(this.selectedId);
    if (comp === undefined || comp.kind !== Kinds.SWITCH) {
      return false;
    }
    comp.value = comp.value === '闭合' ? '断开' : '闭合';
    this.setStatus(`${comp.label} 已${comp.value}`);
    this.touch();
    return true;
  }

  deleteComponent(id: string): void {
    this.pushUndo();
    const kept: CircuitComponent[] = [];
    for (let i = 0; i < this.components.length; i++) {
      if (this.components[i].id !== id) {
        kept.push(this.components[i]);
      }
    }
    this.components = kept;
    hilog.info(0xC001, 'CircuitStore',
      `deleteComponent ${id} left=${this.components.length}`);
    const keptWires: Wire[] = [];
    for (let i = 0; i < this.wires.length; i++) {
      if (this.wires[i].fromId !== id && this.wires[i].toId !== id) {
        keptWires.push(this.wires[i]);
      }
    }
    this.wires = keptWires;
    if (this.selectedId === id) {
      this.selectedId = '';
    }
    this.touch();
  }

  rotateSelected(): void {
    const comp: CircuitComponent | undefined = this.findComponent(this.selectedId);
    if (comp === undefined) {
      return;
    }
    this.pushUndo();
    comp.rotation = (comp.rotation + 90) % 360;
    this.touch();
  }

  selectedComponent(): CircuitComponent | undefined {
    return this.findComponent(this.selectedId);
  }

  /* ---------- 连线 ---------- */

  isWiring(): boolean {
    return this.wireFromId !== '';
  }

  beginWire(compId: string, pinIndex: number): void {
    this.wireFromId = compId;
    this.wireFromPin = pinIndex;
    this.wireBends = [];
    const comp: CircuitComponent | undefined = this.findComponent(compId);
    this.setStatus(`连线中：从 ${comp !== undefined ? comp.label : '?'} 出发，点击另一引脚完成连接`);
    this.touch();
  }

  addWireBend(p: Point): void {
    const snapped: Point = { x: GeometryUtil.snap(p.x), y: GeometryUtil.snap(p.y) };
    this.wireBends.push(snapped);
    this.touch();
  }

  finishWire(compId: string, pinIndex: number): void {
    if (this.wireFromId === '' || compId === this.wireFromId) {
      const wasActive: boolean = this.wireFromId !== '';
      this.cancelWire();
      if (wasActive) {
        this.setStatus('已取消连线（起止为同一引脚）');
      }
      return;
    }
    this.pushUndo();
    const w: Wire = new Wire();
    w.id = this.genId('wire');
    w.fromId = this.wireFromId;
    w.fromPin = this.wireFromPin;
    w.toId = compId;
    w.toPin = pinIndex;
    w.bends = this.wireBends;
    this.wires.push(w);
    this.cancelWire(); // 清理草稿但保持连线模式，方便连续布线
    this.setStatus('已连接导线，可继续从下一个引脚连线（Esc 或右键退出连线）');
    this.touch();
  }

  finishWireDangling(x: number, y: number): void {
    if (this.wireFromId === '') {
      return;
    }
    this.pushUndo();
    const w: Wire = new Wire();
    w.id = this.genId('wire');
    w.fromId = this.wireFromId;
    w.fromPin = this.wireFromPin;
    w.endX = GeometryUtil.snap(x);
    w.endY = GeometryUtil.snap(y);
    w.bends = this.wireBends;
    this.wires.push(w);
    this.cancelWire();
    this.setStatus('导线末端悬空，可继续连线（Esc 或右键退出连线）');
    this.touch();
  }

  cancelWire(): void {
    this.wireFromId = '';
    this.wireFromPin = -1;
    this.wireBends = [];
    this.touch();
  }

  /** 连线预览折线（起点 + 拐点 + 鼠标当前位置） */
  wirePreview(cur: Point): Point[] {
    const pts: Point[] = [];
    const comp: CircuitComponent | undefined = this.findComponent(this.wireFromId);
    if (comp === undefined) {
      return pts;
    }
    pts.push(comp.pinWorld(this.wireFromPin));
    for (let i = 0; i < this.wireBends.length; i++) {
      pts.push(this.wireBends[i]);
    }
    pts.push(cur);
    return pts;
  }

  /* ---------- 标注 ---------- */

  beginStroke(p: Point): void {
    this.pushUndo();
    const s: StrokeNote = new StrokeNote();
    s.id = this.genId('stroke');
    s.color = this.annotationColor;
    s.points.push(p);
    this.strokes.push(s);
    this.selectedId = s.id;
    this.touch();
  }

  appendStrokePoint(p: Point): void {
    const s: StrokeNote | undefined = this.strokes[this.strokes.length - 1];
    if (s === undefined || s.points.length === 0) {
      return;
    }
    const last: Point = s.points[s.points.length - 1];
    if (GeometryUtil.dist(last.x, last.y, p.x, p.y) > 3) {
      s.points.push(p);
      this.touch();
    }
  }

  endStroke(): void {
    const s: StrokeNote | undefined = this.strokes[this.strokes.length - 1];
    if (s !== undefined && s.points.length <= 1) {
      const kept: StrokeNote[] = [];
      for (let i = 0; i < this.strokes.length; i++) {
        if (this.strokes[i] !== s) {
          kept.push(this.strokes[i]);
        }
      }
      this.strokes = kept;
      this.selectedId = '';
    }
    this.touch();
  }

  addText(x: number, y: number, text: string): void {
    if (text.trim() === '') {
      return;
    }
    this.pushUndo();
    const t: TextNote = new TextNote();
    t.id = this.genId('text');
    t.x = x;
    t.y = y;
    t.text = text;
    t.color = this.annotationColor;
    this.texts.push(t);
    this.setStatus('已添加文本标注');
    this.touch();
  }

  setAnnotationColor(color: string): void {
    this.annotationColor = color;
    this.touch();
  }

  /* ---------- 删除 / 清空 ---------- */

  deleteSelected(): void {
    if (this.selectedId === '') {
      return;
    }
    const id: string = this.selectedId;
    if (this.findComponent(id) !== undefined) {
      this.deleteComponent(id);
      this.setStatus('已删除元件（连同其导线）');
      return;
    }
    this.pushUndo();
    const wKept: Wire[] = this.wires.filter((w: Wire): boolean => w.id !== id);
    if (wKept.length !== this.wires.length) {
      this.wires = wKept;
      this.selectedId = '';
      this.setStatus('已删除导线');
      this.touch();
      return;
    }
    const sKept: StrokeNote[] = this.strokes.filter((s: StrokeNote): boolean => s.id !== id);
    if (sKept.length !== this.strokes.length) {
      this.strokes = sKept;
      this.selectedId = '';
      this.setStatus('已删除画笔标注');
      this.touch();
      return;
    }
    const tKept: TextNote[] = this.texts.filter((t: TextNote): boolean => t.id !== id);
    if (tKept.length !== this.texts.length) {
      this.texts = tKept;
      this.selectedId = '';
      this.setStatus('已删除文本标注');
      this.touch();
      return;
    }
  }

  clearAll(): void {
    this.pushUndo();
    this.components = [];
    this.wires = [];
    this.strokes = [];
    this.texts = [];
    this.selectedId = '';
    this.cancelWire();
    this.labelSeq = {};
    this.setStatus('画板已清空');
    this.touch();
  }

  /* ---------- 命中测试 ---------- */

  hitComponent(x: number, y: number): CircuitComponent | undefined {
    for (let i = this.components.length - 1; i >= 0; i--) {
      if (this.components[i].contains(x, y)) {
        return this.components[i];
      }
    }
    return undefined;
  }

  hitPin(x: number, y: number, maxDist: number = 16): PinRef | null {
    for (let i = this.components.length - 1; i >= 0; i--) {
      const comp: CircuitComponent = this.components[i];
      for (let p = 0; p < comp.pinCount(); p++) {
        const pos: Point = comp.pinWorld(p);
        if (GeometryUtil.dist(x, y, pos.x, pos.y) <= maxDist) {
          const ref: PinRef = { compId: comp.id, pinIndex: p };
          return ref;
        }
      }
    }
    return null;
  }

  /** 指定元件上距离最近的引脚（容错命中：点在元件上但没点准引脚时使用） */
  nearestPinOf(comp: CircuitComponent, x: number, y: number, tol: number): PinRef | null {
    let best: PinRef | null = null;
    let bestD: number = tol;
    for (let p = 0; p < comp.pinCount(); p++) {
      const pos: Point = comp.pinWorld(p);
      const d: number = GeometryUtil.dist(x, y, pos.x, pos.y);
      if (d <= bestD) {
        bestD = d;
        const ref: PinRef = { compId: comp.id, pinIndex: p };
        best = ref;
      }
    }
    return best;
  }

  hitWire(x: number, y: number, maxDist: number = 7): Wire | undefined {
    for (let i = this.wires.length - 1; i >= 0; i--) {
      const pts: Point[] = this.wires[i].polyline(this);
      if (GeometryUtil.distToPolyline(x, y, pts) <= maxDist) {
        return this.wires[i];
      }
    }
    return undefined;
  }

  hitStroke(x: number, y: number, maxDist: number = 8): StrokeNote | undefined {
    for (let i = this.strokes.length - 1; i >= 0; i--) {
      if (GeometryUtil.distToPolyline(x, y, this.strokes[i].points) <= maxDist) {
        return this.strokes[i];
      }
    }
    return undefined;
  }

  hitText(x: number, y: number): TextNote | undefined {
    for (let i = this.texts.length - 1; i >= 0; i--) {
      const t: TextNote = this.texts[i];
      const w: number = t.text.length * t.size;
      if (x >= t.x - 4 && x <= t.x + w + 4 && y >= t.y - t.size - 2 && y <= t.y + 6) {
        return t;
      }
    }
    return undefined;
  }

  /** 橡皮擦：依次尝试 标注/导线/元件 */
  eraseAt(x: number, y: number): void {
    const stroke: StrokeNote | undefined = this.hitStroke(x, y);
    if (stroke !== undefined) {
      this.selectedId = stroke.id;
      this.deleteSelected();
      return;
    }
    const text: TextNote | undefined = this.hitText(x, y);
    if (text !== undefined) {
      this.selectedId = text.id;
      this.deleteSelected();
      return;
    }
    const wire: Wire | undefined = this.hitWire(x, y);
    if (wire !== undefined) {
      this.selectedId = wire.id;
      this.deleteSelected();
      return;
    }
    const comp: CircuitComponent | undefined = this.hitComponent(x, y);
    if (comp !== undefined) {
      this.deleteComponent(comp.id);
      this.setStatus('已删除元件');
    }
  }

  /* ---------- 分析记录 ---------- */

  addRecord(title: string, content: string): void {
    const r: AnalysisRecord = new AnalysisRecord();
    r.id = this.genId('rec');
    r.title = title.trim() === '' ? `分析记录 ${this.records.length + 1}` : title.trim();
    r.content = content;
    r.timestamp = Date.now();
    this.records.push(r);
    this.setStatus('已保存分析记录');
  }

  updateRecord(id: string, title: string, content: string): void {
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].id === id) {
        this.records[i].title = title;
        this.records[i].content = content;
        this.records[i].timestamp = Date.now();
        this.touch();
        return;
      }
    }
  }

  deleteRecord(id: string): void {
    const kept: AnalysisRecord[] = this.records.filter((r: AnalysisRecord): boolean => r.id !== id);
    this.records = kept;
    this.touch();
  }

  /* ---------- 持久化 ---------- */

  saveTo(context: common.Context): boolean {
    const ok: boolean = BoardStorage.save(context, this.snapshot());
    this.setStatus(ok ? '画板已保存到本地' : '保存失败');
    return ok;
  }

  loadFrom(context: common.Context): boolean {
    const text: string = BoardStorage.load(context);
    if (text === '') {
      this.setStatus('本地没有已保存的画板');
      return false;
    }
    this.pushUndo();
    this.applySnapshot(text);
    const board: CircuitBoard = reviveBoard(text);
    this.records = board.records;
    this.setStatus(`已载入本地画板「${this.name}」`);
    this.touch();
    return true;
  }

  loadDemo(): void {
    if (!this.hasCanvas()) {
      return;
    }
    this.pushUndo();
    this.components = [];
    this.wires = [];
    this.strokes = [];
    this.texts = [];
    this.labelSeq = {};
    const center: Point = this.canvasCenter();
    const bx: number = GeometryUtil.snap(center.x);
    const by: number = GeometryUtil.snap(center.y);

    const battery: CircuitComponent = this.makeDemoComp(Kinds.BATTERY, 'E1', '12V', bx - 140, by + 100);
    const sw: CircuitComponent = this.makeDemoComp(Kinds.SWITCH, 'S1', '断开', bx - 140, by - 100);
    const resistor: CircuitComponent = this.makeDemoComp(Kinds.RESISTOR, 'R1', '10Ω', bx + 140, by - 100);
    const bulb: CircuitComponent = this.makeDemoComp(Kinds.BULB, 'H1', '6V', bx + 140, by + 100);
    this.components.push(battery);
    this.components.push(sw);
    this.components.push(resistor);
    this.components.push(bulb);

    this.wires.push(this.makeDemoWire(battery, 0, sw, 0));
    this.wires.push(this.makeDemoWire(sw, 1, resistor, 0));
    this.wires.push(this.makeDemoWire(resistor, 1, bulb, 1));
    this.wires.push(this.makeDemoWire(bulb, 0, battery, 1));

    const note: TextNote = new TextNote();
    note.id = this.genId('text');
    note.x = bx - 30;
    note.y = by - 20;
    note.text = '串联回路：闭合 S 观察电流';
    note.color = '#C62828';
    this.texts.push(note);

    if (this.records.length === 0) {
      const r: AnalysisRecord = new AnalysisRecord();
      r.id = this.genId('rec');
      r.title = '示例：欧姆定律试算';
      r.content = '若 U=12V，R=10Ω，则 I = U / R = 1.2A；闭合开关后电流表应显示约 1.2A。';
      r.timestamp = Date.now();
      this.records.push(r);
    }
    this.selectedId = '';
    this.setStatus('已载入示例电路：串联回路');
    this.touch();
  }

  private makeDemoComp(kind: string, label: string, value: string, x: number, y: number): CircuitComponent {
    const c: CircuitComponent = new CircuitComponent();
    c.id = this.genId('comp');
    c.kind = kind;
    c.x = x;
    c.y = y;
    c.rotation = 0;
    c.label = label;
    c.value = value;
    return c;
  }

  private makeDemoWire(from: CircuitComponent, fromPin: number, to: CircuitComponent, toPin: number): Wire {
    const w: Wire = new Wire();
    w.id = this.genId('wire');
    w.fromId = from.id;
    w.fromPin = fromPin;
    w.toId = to.id;
    w.toPin = toPin;
    return w;
  }
}
