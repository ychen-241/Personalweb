/**
 * 电路画板 - 原理图绘制器
 * 负责在 Canvas 上绘制：网格、导线、元件符号、选中态、引脚热点、连线预览、标注
 */
import {
  CircuitBoard, CircuitComponent, Kinds, Point, StrokeNote, TextNote, Wire
} from '../model/CircuitTypes';
import { Mode } from '../model/CircuitTypes';

/** 绘制选项（由视图层传入的界面态） */
export class DrawOptions {
  width: number = 0;
  height: number = 0;
  mode: string = Mode.SELECT;
  selectedId: string = '';
  hoverCompId: string = '';
  hoverPinIndex: number = -1;
  wirePreview: Point[] | null = null;
  grid: boolean = true;
}

export class SchematicRenderer {
  private static readonly GRID: number = 20;
  private static readonly COLOR_WIRE: string = '#2E7D32';
  private static readonly COLOR_WIRE_SELECTED: string = '#F57C00';
  private static readonly COLOR_BODY: string = '#37474F';
  private static readonly COLOR_SELECT: string = '#1976D2';
  private static readonly COLOR_PIN: string = '#1976D2';

  static draw(ctx: CanvasRenderingContext2D, board: CircuitBoard, o: DrawOptions): void {
    // 背景
    ctx.fillStyle = '#FBFCFE';
    ctx.fillRect(0, 0, o.width, o.height);
    if (o.grid) {
      SchematicRenderer.drawGrid(ctx, o.width, o.height);
    }
    // 导线
    for (let i = 0; i < board.wires.length; i++) {
      const w: Wire = board.wires[i];
      const selected: boolean = w.id === o.selectedId && o.mode === Mode.SELECT;
      SchematicRenderer.drawWire(ctx, board, w, selected);
    }
    // 元件
    for (let i = 0; i < board.components.length; i++) {
      const comp: CircuitComponent = board.components[i];
      const selected: boolean = comp.id === o.selectedId && o.mode === Mode.SELECT;
      SchematicRenderer.drawComponent(ctx, comp, selected);
    }
    // 连线模式：引脚热点 + 悬停高亮
    if (o.mode === Mode.WIRE) {
      for (let i = 0; i < board.components.length; i++) {
        const comp: CircuitComponent = board.components[i];
        for (let p = 0; p < comp.pinCount(); p++) {
          const pos: Point = comp.pinWorld(p);
          const hovered: boolean = comp.id === o.hoverCompId && p === o.hoverPinIndex;
          ctx.beginPath();
          ctx.arc(pos.x, pos.y, hovered ? 5.5 : 4, 0, Math.PI * 2);
          if (hovered) {
            ctx.fillStyle = SchematicRenderer.COLOR_PIN;
            ctx.fill();
          } else {
            ctx.strokeStyle = SchematicRenderer.COLOR_PIN;
            ctx.lineWidth = 1.5;
            ctx.stroke();
          }
        }
      }
    }
    // 连线预览
    if (o.wirePreview !== null && o.wirePreview.length >= 2) {
      ctx.save();
      ctx.strokeStyle = SchematicRenderer.COLOR_PIN;
      ctx.lineWidth = 2;
      ctx.setLineDash([6, 4]);
      ctx.beginPath();
      ctx.moveTo(o.wirePreview[0].x, o.wirePreview[0].y);
      for (let i = 1; i < o.wirePreview.length; i++) {
        ctx.lineTo(o.wirePreview[i].x, o.wirePreview[i].y);
      }
      ctx.stroke();
      ctx.restore();
    }
    // 标注层（画笔 + 文本，始终在最上层）
    for (let i = 0; i < board.strokes.length; i++) {
      SchematicRenderer.drawStroke(ctx, board.strokes[i], board.strokes[i].id === o.selectedId && o.mode === Mode.SELECT);
    }
    for (let i = 0; i < board.texts.length; i++) {
      SchematicRenderer.drawText(ctx, board.texts[i], board.texts[i].id === o.selectedId && o.mode === Mode.SELECT);
    }
  }

  private static drawGrid(ctx: CanvasRenderingContext2D, w: number, h: number): void {
    ctx.fillStyle = '#E4E8EF';
    const step: number = SchematicRenderer.GRID;
    for (let x = step; x < w; x += step) {
      for (let y = step; y < h; y += step) {
        ctx.fillRect(x - 1, y - 1, 2, 2);
      }
    }
  }

  private static drawWire(ctx: CanvasRenderingContext2D, board: CircuitBoard, w: Wire, selected: boolean): void {
    const pts: Point[] = w.polyline(board);
    if (pts.length < 2) {
      return;
    }
    ctx.save();
    ctx.strokeStyle = selected ? SchematicRenderer.COLOR_WIRE_SELECTED : SchematicRenderer.COLOR_WIRE;
    ctx.lineWidth = selected ? 4 : 2.5;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(pts[0].x, pts[0].y);
    for (let i = 1; i < pts.length; i++) {
      ctx.lineTo(pts[i].x, pts[i].y);
    }
    ctx.stroke();
    // 端点连接点
    ctx.fillStyle = selected ? SchematicRenderer.COLOR_WIRE_SELECTED : '#1B5E20';
    ctx.beginPath();
    ctx.arc(pts[0].x, pts[0].y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(pts[pts.length - 1].x, pts[pts.length - 1].y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();
  }

  private static drawComponent(ctx: CanvasRenderingContext2D, c: CircuitComponent, selected: boolean): void {
    ctx.save();
    ctx.translate(c.x, c.y);
    ctx.rotate(c.rotation * Math.PI / 180);
    ctx.strokeStyle = SchematicRenderer.COLOR_BODY;
    ctx.fillStyle = '#FFFFFF';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    switch (c.kind) {
      case Kinds.RESISTOR:
        SchematicRenderer.stub(ctx, -20, -10, 10);
        SchematicRenderer.stub(ctx, 10, 20, 10);
        ctx.beginPath();
        ctx.rect(-10, -8, 20, 16);
        ctx.fill();
        ctx.stroke();
        break;
      case Kinds.BATTERY:
        SchematicRenderer.stub(ctx, -20, -6, 6);
        SchematicRenderer.stub(ctx, 6, 20, 6);
        // 长板（正极）
        ctx.beginPath();
        ctx.moveTo(-6, -14);
        ctx.lineTo(-6, 14);
        ctx.stroke();
        // 短板（负极，粗）
        ctx.lineWidth = 4;
        ctx.beginPath();
        ctx.moveTo(6, -7);
        ctx.lineTo(6, 7);
        ctx.stroke();
        break;
      case Kinds.CAPACITOR:
        SchematicRenderer.stub(ctx, -20, -6, 6);
        SchematicRenderer.stub(ctx, 6, 20, 6);
        ctx.beginPath();
        ctx.moveTo(-6, -13);
        ctx.lineTo(-6, 13);
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(6, -13);
        ctx.lineTo(6, 13);
        ctx.stroke();
        break;
      case Kinds.INDUCTOR:
        SchematicRenderer.stub(ctx, -20, -19, 1);
        SchematicRenderer.stub(ctx, 19, 20, 1);
        ctx.beginPath();
        ctx.arc(-13, 0, 6.5, Math.PI, 0, false);
        ctx.arc(0, 0, 6.5, Math.PI, 0, false);
        ctx.arc(13, 0, 6.5, Math.PI, 0, false);
        ctx.stroke();
        break;
      case Kinds.SWITCH:
        SchematicRenderer.stub(ctx, -20, -10, 10);
        SchematicRenderer.stub(ctx, 10, 20, 10);
        ctx.beginPath();
        ctx.arc(-10, 0, 3, 0, Math.PI * 2);
        ctx.fillStyle = SchematicRenderer.COLOR_BODY;
        ctx.fill();
        ctx.beginPath();
        ctx.arc(10, 0, 3, 0, Math.PI * 2);
        ctx.fill();
        ctx.beginPath();
        ctx.moveTo(-10, 0);
        ctx.lineTo(7, -13);
        ctx.stroke();
        break;
      case Kinds.BULB:
        SchematicRenderer.stub(ctx, -20, -14, 14);
        SchematicRenderer.stub(ctx, 14, 20, 14);
        ctx.beginPath();
        ctx.arc(0, 0, 14, 0, Math.PI * 2);
        ctx.fillStyle = '#FFFDE7';
        ctx.fill();
        ctx.stroke();
        ctx.beginPath();
        ctx.moveTo(-9, -9);
        ctx.lineTo(9, 9);
        ctx.moveTo(9, -9);
        ctx.lineTo(-9, 9);
        ctx.stroke();
        break;
      case Kinds.AMMETER:
      case Kinds.VOLTMETER:
        SchematicRenderer.stub(ctx, -20, -14, 14);
        SchematicRenderer.stub(ctx, 14, 20, 14);
        ctx.beginPath();
        ctx.arc(0, 0, 14, 0, Math.PI * 2);
        ctx.fillStyle = '#FFFFFF';
        ctx.fill();
        ctx.stroke();
        ctx.fillStyle = SchematicRenderer.COLOR_BODY;
        ctx.font = 'bold 14px sans-serif';
        ctx.textAlign = 'center';
        ctx.textBaseline = 'middle';
        ctx.fillText(c.kind === Kinds.AMMETER ? 'A' : 'V', 0, 1);
        break;
      case Kinds.GROUND:
        SchematicRenderer.stub(ctx, -20, 0, 20);
        ctx.beginPath();
        ctx.moveTo(-14, 2);
        ctx.lineTo(14, 2);
        ctx.moveTo(-9, 7);
        ctx.lineTo(9, 7);
        ctx.moveTo(-4, 12);
        ctx.lineTo(4, 12);
        ctx.stroke();
        break;
      default:
        break;
    }
    ctx.restore();

    // 标签与参数（世界坐标，不随元件旋转）
    ctx.save();
    ctx.textAlign = 'center';
    ctx.fillStyle = SchematicRenderer.COLOR_SELECT;
    ctx.font = 'bold 12px sans-serif';
    ctx.textBaseline = 'bottom';
    if (c.label !== '') {
      ctx.fillText(c.label, c.x, c.y - 26);
    }
    ctx.fillStyle = '#78909C';
    ctx.font = '11px sans-serif';
    ctx.textBaseline = 'top';
    if (c.value !== '') {
      ctx.fillText(c.value, c.x, c.y + 26);
    }
    ctx.restore();

    // 选中框
    if (selected) {
      const size = c.bodySize();
      const rw: number = (c.rotation === 90 || c.rotation === 270) ? size.h : size.w;
      const rh: number = (c.rotation === 90 || c.rotation === 270) ? size.w : size.h;
      ctx.save();
      ctx.strokeStyle = SchematicRenderer.COLOR_SELECT;
      ctx.lineWidth = 1.5;
      ctx.setLineDash([5, 4]);
      ctx.strokeRect(c.x - rw / 2 - 6, c.y - rh / 2 - 6, rw + 12, rh + 12);
      ctx.restore();
    }
  }

  /** 从 x1 到 x2 画水平引线 */
  private static stub(ctx: CanvasRenderingContext2D, x1: number, x2: number, y: number): void {
    ctx.beginPath();
    ctx.moveTo(x1, y);
    ctx.lineTo(x2, y);
    ctx.stroke();
  }

  private static drawStroke(ctx: CanvasRenderingContext2D, s: StrokeNote, selected: boolean): void {
    if (s.points.length === 0) {
      return;
    }
    ctx.save();
    ctx.strokeStyle = selected ? SchematicRenderer.COLOR_SELECT : s.color;
    ctx.lineWidth = selected ? s.width + 2 : s.width;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(s.points[0].x, s.points[0].y);
    for (let i = 1; i < s.points.length; i++) {
      ctx.lineTo(s.points[i].x, s.points[i].y);
    }
    if (s.points.length === 1) {
      ctx.lineTo(s.points[0].x + 0.5, s.points[0].y + 0.5);
    }
    ctx.stroke();
    ctx.restore();
  }

  private static drawText(ctx: CanvasRenderingContext2D, t: TextNote, selected: boolean): void {
    ctx.save();
    ctx.font = `${t.size}px sans-serif`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
    ctx.fillStyle = selected ? SchematicRenderer.COLOR_SELECT : t.color;
    ctx.fillText(t.text, t.x, t.y);
    if (selected) {
      const w: number = t.text.length * t.size;
      ctx.strokeStyle = SchematicRenderer.COLOR_SELECT;
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(t.x - 4, t.y - t.size, w + 8, t.size + 8);
    }
    ctx.restore();
  }
}
