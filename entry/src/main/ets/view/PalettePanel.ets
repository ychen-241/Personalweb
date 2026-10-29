/**
 * 电路画板 - 左侧面板：编辑模式 / 元件库 / 画板操作
 */
import { KIND_LIST, KindMeta, Mode } from '../model/CircuitTypes';
import { CircuitStore } from '../viewmodel/CircuitStore';
import { common } from '@kit.AbilityKit';

interface ModeItem {
  mode: string;
  name: string;
  icon: string;
}

const MODES: ModeItem[] = [
  { mode: Mode.SELECT, name: '选择', icon: '⬚' },
  { mode: Mode.WIRE, name: '连线', icon: '⌇' },
  { mode: Mode.PEN, name: '画笔', icon: '✎' },
  { mode: Mode.TEXT, name: '文字', icon: '𝐓' },
  { mode: Mode.ERASER, name: '擦除', icon: '⌫' }
];

const NOTE_COLORS: string[] = ['#E53935', '#1E88E5', '#F9A825'];

@ComponentV2
export struct PalettePanel {
  @Param store: CircuitStore = new CircuitStore();

  private hostContext(): common.Context | undefined {
    return this.getUIContext().getHostContext();
  }

  @Builder
  private modeButtons() {
    Row({ space: 4 }) {
      ForEach(MODES, (m: ModeItem) => {
        Text(`${m.icon}\n${m.name}`)
          .fontSize(10)
          .textAlign(TextAlign.Center)
          .lineHeight(14)
          .fontColor(this.store.mode === m.mode ? '#FFFFFF' : '#37474F')
          .backgroundColor(this.store.mode === m.mode ? '#1976D2' : '#F1F3F7')
          .borderRadius(8)
          .padding({ top: 6, bottom: 6 })
          .layoutWeight(1)
          .onClick(() => {
            this.store.setMode(m.mode);
          })
      }, (m: ModeItem) => m.mode)
    }
    .width('100%')
  }

  @Builder
  private noteColors() {
    Row({ space: 8 }) {
      Text('标注色').fontSize(11).fontColor('#78909C')
      ForEach(NOTE_COLORS, (c: string) => {
        Text('●')
          .fontSize(18)
          .fontColor(c)
          .width(22)
          .height(22)
          .textAlign(TextAlign.Center)
          .borderRadius(11)
          .border({ width: this.store.annotationColor === c ? 2 : 0, color: '#263238' })
          .onClick(() => {
            this.store.setAnnotationColor(c);
          })
      }, (c: string) => c)
    }
    .width('100%')
  }

  @Builder
  private actionButtons() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Button('保存')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .onClick(() => {
            const ctx: common.Context | undefined = this.hostContext();
            if (ctx !== undefined) {
              this.store.saveTo(ctx);
            }
          })
        Button('载入')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .onClick(() => {
            const ctx: common.Context | undefined = this.hostContext();
            if (ctx !== undefined) {
              this.store.loadFrom(ctx);
            }
          })
      }
      Row({ space: 6 }) {
        Button('撤销')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .opacity(this.store.undoDepth > 0 ? 1 : 0.4)
          .onClick(() => {
            this.store.undo();
          })
        Button('重做')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .opacity(this.store.redoDepth > 0 ? 1 : 0.4)
          .onClick(() => {
            this.store.redo();
          })
        Button('删除')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .backgroundColor('#ECEFF1')
          .fontColor('#C62828')
          .onClick(() => {
            this.store.deleteSelected();
          })
      }
      Row({ space: 6 }) {
        Button('示例电路')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .onClick(() => {
            this.store.loadDemo();
          })
        Button('清空画板')
          .buttonStyle(ButtonStyleMode.NORMAL)
          .layoutWeight(1)
          .backgroundColor('#ECEFF1')
          .fontColor('#C62828')
          .onClick(() => {
            this.store.clearAll();
          })
      }
    }
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      Text('电路学习画板')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#263238')
        .width('100%')

      Text('编辑模式')
        .fontSize(11)
        .fontColor('#78909C')
        .width('100%')
      this.modeButtons()

      Divider().color('#ECEFF1')

      Text('元件库（点击添加）')
        .fontSize(11)
        .fontColor('#78909C')
        .width('100%')
      Column({ space: 6 }) {
        ForEach(KIND_LIST, (meta: KindMeta) => {
          Row({ space: 8 }) {
            Text(meta.name)
              .fontSize(13)
              .fontColor('#263238')
              .layoutWeight(1)
            Text(meta.defaultValue === '' ? '—' : meta.defaultValue)
              .fontSize(11)
              .fontColor('#90A4AE')
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 8 })
          .backgroundColor('#F8FAFC')
          .borderRadius(8)
          .border({ width: 1, color: '#E3E8F0' })
          .onClick(() => {
            this.store.addComponent(meta.kind);
          })
        }, (meta: KindMeta) => meta.kind)
      }
      .alignItems(HorizontalAlign.Start)

      Divider().color('#ECEFF1')

      if (this.store.mode === Mode.PEN || this.store.mode === Mode.TEXT) {
        this.noteColors()
      }

      this.actionButtons()
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#FFFFFF')
    .alignItems(HorizontalAlign.Start)
  }
}
