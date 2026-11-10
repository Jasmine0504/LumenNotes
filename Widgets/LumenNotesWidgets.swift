import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct NewNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.lumen.notes.control.new") {
            ControlWidgetButton(action: CreateNoteIntent()) {
                Label("新建备忘录", systemImage: "square.and.pencil")
            }
        }
        .displayName("新建备忘录")
        .description("打开流明笔记并立即开始输入。")
    }
}

@main
struct LumenNotesWidgets: WidgetBundle {
    var body: some Widget {
        NewNoteControl()
    }
}
