/**
 * 电路画板 - 几何工具（命中测试等）
 */
import { Point } from '../model/CircuitTypes';

export class GeometryUtil {
  /** 两点距离 */
  static dist(ax: number, ay: number, bx: number, by: number): number {
    const dx: number = ax - bx;
    const dy: number = ay - by;
    return Math.sqrt(dx * dx + dy * dy);
  }

  /** 点到线段的最短距离 */
  static distToSegment(px: number, py: number, ax: number, ay: number, bx: number, by: number): number {
    const abx: number = bx - ax;
    const aby: number = by - ay;
    const apx: number = px - ax;
    const apy: number = py - ay;
    const lenSq: number = abx * abx + aby * aby;
    if (lenSq === 0) {
      return GeometryUtil.dist(px, py, ax, ay);
    }
    let t: number = (apx * abx + apy * aby) / lenSq;
    t = Math.max(0, Math.min(1, t));
    return GeometryUtil.dist(px, py, ax + abx * t, ay + aby * t);
  }

  /** 点到折线的最短距离 */
  static distToPolyline(px: number, py: number, pts: Point[]): number {
    if (pts.length === 0) {
      return Number.MAX_VALUE;
    }
    if (pts.length === 1) {
      return GeometryUtil.dist(px, py, pts[0].x, pts[0].y);
    }
    let min: number = Number.MAX_VALUE;
    for (let i = 0; i < pts.length - 1; i++) {
      const d: number = GeometryUtil.distToSegment(px, py, pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y);
      if (d < min) {
        min = d;
      }
    }
    return min;
  }

  /** 吸附到网格 */
  static snap(v: number, grid: number = 20): number {
    return Math.round(v / grid) * grid;
  }

  /** 在数组中找最近点，返回索引；超过 maxDist 返回 -1 */
  static nearestPointIndex(px: number, py: number, pts: Point[], maxDist: number): number {
    let best: number = -1;
    let bestD: number = maxDist;
    for (let i = 0; i < pts.length; i++) {
      const d: number = GeometryUtil.dist(px, py, pts[i].x, pts[i].y);
      if (d <= bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /** 时间戳 -> yyyy-MM-dd HH:mm */
  static formatTime(ts: number): string {
    const d: Date = new Date(ts);
    const pad = (n: number): string => n < 10 ? '0' + n : '' + n;
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }
}
