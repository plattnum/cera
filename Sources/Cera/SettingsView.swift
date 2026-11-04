import SwiftUI

/// Cera ▸ Settings… (⌘,). The column width slider's two settings (see `ColumnWidth`): the percentage the slider goes
/// back to, and how long the slider is in the status bar.
struct SettingsView: View {
    @AppStorage(ColumnWidth.defaultKey) private var defaultPercent = 20.0
    @AppStorage(ColumnWidth.sliderLengthKey) private var sliderLength = 150.0

    var body: some View {
        let percent = Binding(get: { ColumnWidth.clamped(defaultPercent) }, set: { defaultPercent = $0 })
        let length = Binding(get: { ColumnWidth.clampedSliderLength(sliderLength) }, set: { sliderLength = $0 })
        Form {
            Section {
                LabeledContent("Default width") {
                    HStack(spacing: 10) {
                        Slider(value: percent, in: 0...100, step: 5)
                        Text("\(Int(percent.wrappedValue.rounded()))%")
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                }
                LabeledContent("Slider length") {
                    Stepper(value: length, in: 80...400, step: 10) {
                        Text("\(Int(length.wrappedValue.rounded())) pt")
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("Column width")
            } footer: {
                Text("0% is the theme's column; 100% is the whole window. The slider at the right of the status bar changes the width as you read, and shows once the window is wider than the theme's column. Double-click its number to go back to the default width.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
