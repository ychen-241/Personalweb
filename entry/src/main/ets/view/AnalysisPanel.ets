/**
 * 电路画板 - 右侧面板：手动记录电路分析结果
 */
import { AnalysisRecord } from '../model/CircuitTypes';
import { CircuitStore } from '../viewmodel/CircuitStore';
import { GeometryUtil } from '../common/GeometryUtil';

@ComponentV2
export struct AnalysisPanel {
  @Param store: CircuitStore = new CircuitStore();
  @Local showEditor: boolean = false;
  @Local editId: string = '';
  @Local draftTitle: string = '';
  @Local draftContent: string = '';

  private openNew(): void {
    this.editId = '';
    this.draftTitle = '';
    this.draftContent = '';
    this.showEditor = true;
  }

  private openEdit(record: AnalysisRecord): void {
    this.editId = record.id;
    this.draftTitle = record.title;
    this.draftContent = record.content;
    this.showEditor = true;
  }

  private commit(): void {
    if (this.editId === '') {
      this.store.addRecord(this.draftTitle, this.draftContent);
    } else {
      this.store.updateRecord(this.editId, this.draftTitle, this.draftContent);
    }
    this.showEditor = false;
  }

  @Builder
  private recordCard(record: AnalysisRecord) {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        Text(record.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor('#263238')
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(GeometryUtil.formatTime(record.timestamp))
          .fontSize(10)
          .fontColor('#90A4AE')
      }
      .width('100%')
      Text(record.content === '' ? '（无内容）' : record.content)
        .fontSize(12)
        .fontColor('#546E7A')
        .width('100%')
        .maxLines(4)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 6 }) {
        Blank()
        Text('编辑')
          .fontSize(11)
          .fontColor('#1976D2')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor('#E3F2FD')
          .onClick(() => {
            this.openEdit(record);
          })
        Text('删除')
          .fontSize(11)
          .fontColor('#C62828')
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(6)
          .backgroundColor('#FFEBEE')
          .onClick(() => {
            this.store.deleteRecord(record.id);
          })
      }
      .width('100%')
    }
    .padding(10)
    .borderRadius(10)
    .backgroundColor('#F8FAFC')
    .border({ width: 1, color: '#E3E8F0' })
    .width('100%')
  }

  @Builder
  private editor() {
    if (this.showEditor) {
      Column() {
        Column({ space: 10 }) {
          Text(this.editId === '' ? '新增分析记录' : '编辑分析记录')
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor('#263238')
          TextInput({ text: this.draftTitle, placeholder: '标题，如：串联电路电流计算' })
            .height(36)
            .onChange((v: string) => {
              this.draftTitle = v;
            })
          TextArea({ text: this.draftContent, placeholder: '手动记录分析过程与结论，如：U=12V，R1=10Ω，则 I=1.2A…' })
            .height(140)
            .onChange((v: string) => {
              this.draftContent = v;
            })
          Row({ space: 10 }) {
            Button('取消')
              .buttonStyle(ButtonStyleMode.NORMAL)
              .layoutWeight(1)
              .onClick(() => {
                this.showEditor = false;
              })
            Button('保存记录')
              .buttonStyle(ButtonStyleMode.EMPHASIZED)
              .layoutWeight(1)
              .onClick(() => {
                this.commit();
              })
          }
        }
        .padding(16)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0,0,0,0.25)')
      .justifyContent(FlexAlign.Center)
      .padding(24)
      .onClick(() => {
        this.showEditor = false;
      })
    }
  }

  build() {
    Stack() {
      Column({ space: 10 }) {
        Row() {
          Text('分析记录')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#263238')
            .layoutWeight(1)
          Text(`共 ${this.store.records.length} 条`)
            .fontSize(10)
            .fontColor('#90A4AE')
          Button('+ 新增')
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .height(28)
            .fontSize(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.openNew();
            })
        }
        .width('100%')

        Text('在搭好电路后，把你的计算与结论手动记录在这里（随画板一起保存到本地）。')
          .fontSize(10)
          .fontColor('#90A4AE')
          .width('100%')

        if (this.store.records.length === 0) {
          Column({ space: 8 }) {
            Text('📝').fontSize(30)
            Text('还没有分析记录')
              .fontSize(12)
              .fontColor('#90A4AE')
            Text('点击右上角「+ 新增」开始记录')
              .fontSize(10)
              .fontColor('#B0BEC5')
          }
          .width('100%')
          .margin({ top: 60 })
        } else {
          List({ space: 8 }) {
            ForEach(this.store.records, (record: AnalysisRecord) => {
              ListItem() {
                this.recordCard(record)
              }
            }, (record: AnalysisRecord) => record.id)
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
        }
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .backgroundColor('#FFFFFF')

      this.editor()
    }
    .width('100%')
    .height('100%')
  }
}
