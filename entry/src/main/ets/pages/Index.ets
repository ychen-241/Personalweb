/**
 * 鸿蒙 PC 校园应用 - 电路学习可视化画板
 * 三栏布局：元件库 | 画板（连线 + 标注） | 分析记录
 */
import { CircuitStore } from '../viewmodel/CircuitStore';
import { PalettePanel } from '../view/PalettePanel';
import { CanvasBoard } from '../view/CanvasBoard';
import { AnalysisPanel } from '../view/AnalysisPanel';

@Entry
@ComponentV2
struct Index {
  @Local store: CircuitStore = new CircuitStore();

  build() {
    Row({ space: 8 }) {
      Column() {
        PalettePanel({ store: this.store })
      }
      .width(210)
      .height('100%')

      Column() {
        CanvasBoard({ store: this.store })
      }
      .layoutWeight(1)
      .height('100%')

      Column() {
        AnalysisPanel({ store: this.store })
      }
      .width(300)
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(8)
    .backgroundColor('#EDF1F7')
  }
}
