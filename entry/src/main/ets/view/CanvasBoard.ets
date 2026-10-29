/**
 * 电路画板 - 中央画板：Canvas 绘制 + 手势交互（点选/连线/标注）+ 属性面板
 *
 * 交互通道说明（均走内置手势系统，模拟器/真机/预览器一致可靠）：
 * - TapGesture   所有「点一下」的动作：选中、连线起止、放置文本、擦除
 * - PanGesture   所有「按住拖动」的动作：移动元件、画笔连续绘制、橡皮擦涂抹、连线预览
 * - onMouse      仅保留悬停引脚高亮与右键快捷操作（不可用时功能不受影响）
 * - onKeyEvent   Esc 取消 / Del 删除 / 方向键微调 / Z Y 撤销重做
 */
import { Point, Mode, CircuitComponent, Kinds } from '../model/CircuitTypes';
import { CircuitStore } from '../viewmodel/CircuitStore';
import { SchematicRenderer } from '../common/SchematicRenderer';
import { DrawOptions } from '../common/SchematicRenderer';
import { GeometryUtil } from '../common/GeometryUtil';
import { KeyCode } from '@ohos.multimodalInput.keyCode';
import { hilog } from '@kit.PerformanceAnalysisKit';

@ComponentV2
export struct CanvasBoard {
  @Param store: CircuitStore = new CircuitStore();
  @Local areaW: number = 800;
  @Local areaH: number = 520;

  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private ctx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  /** 拖拽状态 */
  private dragId: string = '';
  private dragOffX: number = 0;
  private dragOffY: number = 0;
  private dragMoved: boolean = false;

  /** 拖拽手势基准点（onActionStart 时的位置） */
  private panBaseX: number = 0;
  private panBaseY: number = 0;

  /** 双击检测 */
  private lastTapTime: number = 0;
  private lastTapX: number = 0;
  private lastTapY: number = 0;

  /** 鼠标/手势当前位置（连线预览用） */
  private mouseX: number = 0;
  private mouseY: number = 0;

  /** 文本标注对话框 */
  @Local showTextDialog: boolean = false;
  @Local textDraft: string = '';
  private pendingTextX: number = 0;
  private pendingTextY: number = 0;

  aboutToAppear(): void {
    this.store.setRedrawer((): void => this.redraw());
  }

  aboutToDisappear(): void {
    this.store.setRedrawer(null);
  }

  private redraw(): void {
    const o: DrawOptions = new DrawOptions();
    o.width = this.areaW;
    o.height = this.areaH;
    o.mode = this.store.mode;
    o.selectedId = this.store.selectedId;
    o.hoverCompId = this.store.hoverCompId;
    o.hoverPinIndex = this.store.hoverPinIndex;
    o.grid = true;
    if (this.store.isWiring()) {
      const p: Point = { x: this.mouseX, y: this.mouseY };
      o.wirePreview = this.store.wirePreview(p);
    }
    try {
      SchematicRenderer.draw(this.ctx, this.store, o);
    } catch (err) {
      // 绘制异常不能中断后续交互，记录日志便于定位
      hilog.error(0xC001, 'CircuitBoard draw error: %{public}s', JSON.stringify(err));
    }
  }

  private log(msg: string): void {
    hilog.info(0xC001, 'CircuitBoard %{public}s', msg);
  }

  /** 从手势事件取组件相对坐标（vp） */
  private gesturePoint(event: GestureEvent): Point {
    if (event.fingerList.length > 0) {
      const f = event.fingerList[0];
      const p: Point = { x: f.localX, y: f.localY };
      return p;
    }
    const p0: Point = { x: this.mouseX, y: this.mouseY };
    return p0;
  }

  /* ---------------- 点击（TapGesture） ---------------- */

  private onTap(x: number, y: number): void {
    this.mouseX = x;
    this.mouseY = y;
    const store: CircuitStore = this.store;
    this.log(`tap(${Math.round(x)},${Math.round(y)}) mode=${store.mode} comps=${store.components.length} wires=${store.wires.length}`);
    switch (store.mode) {
      case Mode.SELECT: {
        const now: number = Date.now();
        const isDouble: boolean = (now - this.lastTapTime < 350)
          && GeometryUtil.dist(x, y, this.lastTapX, this.lastTapY) < 8;
        this.lastTapTime = now;
        this.lastTapX = x;
        this.lastTapY = y;
        // 精确点中引脚（10px 内）→ 直接进入连线
        const pin = store.hitPin(x, y, 10);
        if (pin !== null) {
          store.setMode(Mode.WIRE);
          store.beginWire(pin.compId, pin.pinIndex);
          return;
        }
        const comp: CircuitComponent | undefined = store.hitComponent(x, y);
        if (comp !== undefined) {
          store.selectedId = comp.id;
          if (isDouble && comp.kind === Kinds.SWITCH) {
            store.toggleSelectedSwitch();
            return;
          }
          store.setStatus(`已选中 ${comp.label}：拖动移动 / 方向键微调 / 面板删除`);
          store.touch();
          return;
        }
        const wire = store.hitWire(x, y);
        if (wire !== undefined) {
          store.selectedId = wire.id;
          store.setStatus('已选中导线：Del 或「删除」按钮删除');
        } else {
          const stroke = store.hitStroke(x, y);
          if (stroke !== undefined) {
            store.selectedId = stroke.id;
            store.setStatus('已选中画笔标注：Del 删除');
          } else {
            const text = store.hitText(x, y);
            if (text !== undefined) {
              store.selectedId = text.id;
              store.setStatus('已选中文本标注：Del 删除');
            } else {
              store.selectedId = '';
              store.setStatus('空白处：未选中对象。删除请先点选目标，或用橡皮擦模式');
            }
          }
        }
        store.touch();
        break;
      }
      case Mode.WIRE: {
        let pin = store.hitPin(x, y);
        if (pin === null) {
          // 容错：点在元件本体附近时，吸附到该元件最近的引脚
          const comp: CircuitComponent | undefined = store.hitComponent(x, y);
          if (comp !== undefined) {
            pin = store.nearestPinOf(comp, x, y, 34);
          }
        }
        if (pin !== null) {
          if (!store.isWiring()) {
            store.beginWire(pin.compId, pin.pinIndex);
          } else {
            store.finishWire(pin.compId, pin.pinIndex);
            this.log(`wire finished comps=${store.components.length} wires=${store.wires.length}`);
          }
        } else if (store.isWiring()) {
          // 距离任何引脚都很近时不加拐点，防止手滑产生多余折线
          const near = store.hitPin(x, y, 20);
          if (near === null) {
            store.addWireBend({ x: x, y: y } as Point);
          }
        } else {
          store.setStatus('请点击元件的蓝色引脚圆点开始连线（点元件本体也可）');
        }
        break;
      }
      case Mode.PEN: {
        store.beginStroke({ x: x, y: y } as Point);
        break;
      }
      case Mode.TEXT: {
        this.pendingTextX = x;
        this.pendingTextY = y;
        this.textDraft = '';
        this.showTextDialog = true;
        break;
      }
      case Mode.ERASER: {
        store.eraseAt(x, y);
        break;
      }
      default:
        break;
    }
  }

  /* ---------------- 拖拽（PanGesture） ---------------- */

  private onPanStart(x: number, y: number): void {
    this.panBaseX = x;
    this.panBaseY = y;
    this.mouseX = x;
    this.mouseY = y;
    const store: CircuitStore = this.store;
    switch (store.mode) {
      case Mode.SELECT: {
        const comp: CircuitComponent | undefined = store.hitComponent(x, y);
        if (comp !== undefined) {
          store.selectedId = comp.id;
          this.dragId = comp.id;
          this.dragOffX = x - comp.x;
          this.dragOffY = y - comp.y;
          this.dragMoved = false;
        }
        break;
      }
      case Mode.PEN: {
        store.beginStroke({ x: x, y: y } as Point);
        break;
      }
      case Mode.ERASER: {
        store.eraseAt(x, y);
        break;
      }
      case Mode.WIRE: {
        if (store.isWiring()) {
          store.touch(); // 预览线锚定到按下位置
        }
        break;
      }
      default:
        break;
    }
  }

  private onPanUpdate(dx: number, dy: number): void {
    const absX: number = this.panBaseX + dx;
    const absY: number = this.panBaseY + dy;
    this.mouseX = absX;
    this.mouseY = absY;
    const store: CircuitStore = this.store;
    switch (store.mode) {
      case Mode.SELECT: {
        if (this.dragId !== '') {
          const comp: CircuitComponent | undefined = store.findComponent(this.dragId);
          if (comp !== undefined) {
            const nx: number = GeometryUtil.snap(absX - this.dragOffX);
            const ny: number = GeometryUtil.snap(absY - this.dragOffY);
            if (nx !== comp.x || ny !== comp.y) {
              if (!this.dragMoved) {
                store.pushUndo(); // 只在真正移动时记撤销
                this.dragMoved = true;
              }
              comp.x = nx;
              comp.y = ny;
              store.touch();
            }
          }
        }
        break;
      }
      case Mode.PEN: {
        store.appendStrokePoint({ x: absX, y: absY } as Point);
        break;
      }
      case Mode.WIRE: {
        if (store.isWiring()) {
          store.touch(); // 预览线跟随
        }
        break;
      }
      case Mode.ERASER: {
        store.eraseAt(absX, absY);
        break;
      }
      default:
        break;
    }
  }

  private onPanEnd(): void {
    const store: CircuitStore = this.store;
    if (store.mode === Mode.SELECT) {
      this.dragId = '';
    } else if (store.mode === Mode.PEN) {
      store.endStroke();
    }
  }

  /* ---------------- 悬停与右键（onMouse，可选增强） ---------------- */

  private onMouseMove(x: number, y: number): void {
    this.mouseX = x;
    this.mouseY = y;
    const store: CircuitStore = this.store;
    if (store.isWiring()) {
      store.touch(); // 刷新预览线
      return;
    }
    if (store.mode === Mode.WIRE || store.mode === Mode.SELECT) {
      const pin = store.hitPin(x, y);
      const cid: string = pin !== null ? pin.compId : '';
      const pidx: number = pin !== null ? pin.pinIndex : -1;
      if (cid !== store.hoverCompId || pidx !== store.hoverPinIndex) {
        store.hoverCompId = cid;
        store.hoverPinIndex = pidx;
        store.touch();
      }
    }
  }

  private onMouseRight(x: number, y: number): void {
    const store: CircuitStore = this.store;
    if (store.mode === Mode.WIRE && store.isWiring()) {
      store.finishWireDangling(x, y);
    } else {
      store.selectedId = '';
      store.touch();
    }
  }

  /* ---------------- 键盘 ---------------- */

  private onKey(keyCode: number): void {
    const store: CircuitStore = this.store;
    if (keyCode === KeyCode.KEYCODE_ESCAPE) {
      if (store.isWiring()) {
        store.cancelWire();
        store.setStatus('已取消连线');
      } else {
        store.selectedId = '';
        store.touch();
      }
    } else if (keyCode === KeyCode.KEYCODE_DEL || keyCode === KeyCode.KEYCODE_FORWARD_DEL) {
      if (store.isWiring()) {
        store.cancelWire();
      } else {
        store.deleteSelected();
      }
    } else if (keyCode === KeyCode.KEYCODE_DPAD_UP) {
      store.moveSelected(0, -20);
    } else if (keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
      store.moveSelected(0, 20);
    } else if (keyCode === KeyCode.KEYCODE_DPAD_LEFT) {
      store.moveSelected(-20, 0);
    } else if (keyCode === KeyCode.KEYCODE_DPAD_RIGHT) {
      store.moveSelected(20, 0);
    } else if (keyCode === KeyCode.KEYCODE_Z) {
      store.undo();
    } else if (keyCode === KeyCode.KEYCODE_Y) {
      store.redo();
    }
  }

  /* ---------------- 界面 ---------------- */

  @Builder
  private propertyPanel() {
    Column({ space: 8 }) {
      if (this.store.mode === Mode.SELECT) {
        if (this.store.selectedComponent() !== undefined) {
          Text(`元件属性 · ${this.store.selectedComponent()!.label}`)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1976D2')
          Row({ space: 6 }) {
            Text('名称').fontSize(11).fontColor('#78909C').width(32)
            TextInput({ text: this.store.selectedComponent()!.label })
              .height(30)
              .layoutWeight(1)
              .fontSize(12)
              .onChange((v: string) => {
                this.store.selectedComponent()!.label = v;
                this.store.touch();
              })
          }
          Row({ space: 6 }) {
            Text('参数').fontSize(11).fontColor('#78909C').width(32)
            TextInput({ text: this.store.selectedComponent()!.value })
              .height(30)
              .layoutWeight(1)
              .fontSize(12)
              .onChange((v: string) => {
                this.store.selectedComponent()!.value = v;
                this.store.touch();
              })
          }
          Row({ space: 6 }) {
            Text('位置').fontSize(11).fontColor('#78909C').width(32)
            Button('←')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .width(38)
              .height(28)
              .fontSize(12)
              .onClick(() => {
                this.store.moveSelected(-20, 0);
              })
            Button('↑')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .width(38)
              .height(28)
              .fontSize(12)
              .onClick(() => {
                this.store.moveSelected(0, -20);
              })
            Button('↓')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .width(38)
              .height(28)
              .fontSize(12)
              .onClick(() => {
                this.store.moveSelected(0, 20);
              })
            Button('→')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .width(38)
              .height(28)
              .fontSize(12)
              .onClick(() => {
                this.store.moveSelected(20, 0);
              })
          }
          if (this.store.selectedComponent()!.kind === Kinds.SWITCH) {
            Button(this.store.selectedComponent()!.value === '闭合' ? '断开开关' : '闭合开关')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .width('100%')
              .height(28)
              .fontSize(12)
              .fontColor('#2E7D32')
              .onClick(() => {
                this.store.toggleSelectedSwitch();
              })
          }
          Row({ space: 6 }) {
            Button('旋转 90°')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .height(28)
              .fontSize(12)
              .layoutWeight(1)
              .onClick(() => {
                this.store.rotateSelected();
              })
            Button('删除')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .height(28)
              .fontSize(12)
              .layoutWeight(1)
              .backgroundColor('#ECEFF1')
              .fontColor('#C62828')
              .onClick(() => {
                this.store.deleteSelected();
              })
          }
        } else if (this.store.selectedId !== '') {
          Row({ space: 6 }) {
            Text('已选中导线/标注')
              .fontSize(11)
              .fontColor('#78909C')
              .layoutWeight(1)
            Button('删除')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .height(28)
              .fontSize(12)
              .backgroundColor('#FFEBEE')
              .fontColor('#C62828')
              .onClick(() => {
                this.store.deleteSelected();
              })
          }
          .width('100%')
        }
      }
    }
    .padding(10)
    .backgroundColor('#FFFFFF')
    .borderRadius(10)
    .border({ width: 1, color: '#E3E8F0' })
    .shadow({ radius: 8, color: 'rgba(0,0,0,0.06)', offsetY: 2 })
    .width(220)
  }

  @Builder
  private textDialog() {
    if (this.showTextDialog) {
      Column() {
        Column({ space: 12 }) {
          Text('添加文本标注').fontSize(14).fontWeight(FontWeight.Bold).fontColor('#263238')
          TextInput({ placeholder: '输入说明文字，如：此处并联一个电压表' })
            .height(38)
            .onChange((v: string) => {
              this.textDraft = v;
            })
          Row({ space: 10 }) {
            Button('取消')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .layoutWeight(1)
              .onClick(() => {
                this.showTextDialog = false;
              })
            Button('添加')
              .buttonStyle(ButtonStyleMode.EMPHASIZED)
              .layoutWeight(1)
              .onClick(() => {
                this.store.addText(this.pendingTextX, this.pendingTextY, this.textDraft);
                this.showTextDialog = false;
              })
          }
        }
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .width(320)
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.25)')
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.showTextDialog = false;
      })
    }
  }

  build() {
    Column({ space: 6 }) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Canvas(this.ctx)
          .width('100%')
          .height('100%')
          .onReady(() => {
            this.redraw();
          })
          .gesture(
            TapGesture({ count: 1 })
              .onAction((event: GestureEvent) => {
                const p: Point = this.gesturePoint(event);
                this.onTap(p.x, p.y);
              })
          )
          .gesture(
            PanGesture({ fingers: 1, distance: 5 })
              .onActionStart((event: GestureEvent) => {
                const p: Point = this.gesturePoint(event);
                this.onPanStart(p.x, p.y);
              })
              .onActionUpdate((event: GestureEvent) => {
                this.onPanUpdate(event.offsetX, event.offsetY);
              })
              .onActionEnd(() => {
                this.log('pan end');
                this.onPanEnd();
              })
              .onActionCancel(() => {
                this.log('pan cancel');
                this.onPanEnd();
              })
          )
          .onMouse((event: MouseEvent) => {
            if (event.action === MouseAction.Move) {
              this.onMouseMove(event.x, event.y);
            } else if (event.action === MouseAction.Press && event.button === MouseButton.Right) {
              this.onMouseRight(event.x, event.y);
            }
          })
          .focusable(true)
          .focusOnTouch(true)
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down) {
              this.onKey(event.keyCode);
            }
          })

        this.propertyPanel()
        this.textDialog()
      }
      .width('100%')
      .layoutWeight(1)
      .onAreaChange((_old: Area, now: Area) => {
        // 量化取整且变化≥1px才更新，避免亚像素抖动引起 Canvas 反复重置（元件闪烁消失）
        const w: number = Math.floor(Number(now.width));
        const h: number = Math.floor(Number(now.height));
        if (Math.abs(w - this.areaW) >= 1 || Math.abs(h - this.areaH) >= 1) {
          this.areaW = w;
          this.areaH = h;
          this.store.setCanvasSize(w, h);
          this.redraw();
        }
      })

      Row({ space: 8 }) {
        Text('状态').fontSize(11).fontColor('#90A4AE')
        Text(`元件${this.store.components.length} 导线${this.store.wires.length}`)
          .fontSize(10)
          .fontColor('#1976D2')
        Text(this.store.statusText)
          .fontSize(12)
          .fontColor('#546E7A')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('拖动/方向键移动 · 点引脚连线 · 双击开关 · Esc 取消 · Del 删除 · Z/Y 撤销')
          .fontSize(10)
          .fontColor('#B0BEC5')
      }
      .width('100%')
      .padding({ left: 12, right: 12, bottom: 4 })
    }
    .width('100%')
    .height('100%')
  }
}
