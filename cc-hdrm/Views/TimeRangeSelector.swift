import SwiftUI

/// Segmented button control for selecting a time range in the analytics window.
///
/// Renders each `TimeRange` case as a button. The selected button uses a filled
/// background; unselected buttons use a clear/outline style.
struct TimeRangeSelector: View {
    @Binding var selected: TimeRange

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimeRange.allCases, id: \.self) { range in
                Button(action: {
                    selected = range
                }) {
                    Text(range.displayLabel)
                        .font(.caption)
                        .fontWeight(selected == range ? .semibold : .regular)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selected == range
                                ? Color.accentColor
                                : Color.clear
                        )
                        .foregroundStyle(
                            selected == range
                                ? Color.white
                                : Color.secondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    selected == range
                                        ? Color.clear
                                        : Color.secondary.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(range.accessibilityDescription)
                .accessibilityAddTraits(selected == range ? .isSelected : [])
            }
        }
    }
}

#if DEBUG
#Preview {
    TimeRangeSelector(selected: .constant(.week))
        .padding()
}
#endif
