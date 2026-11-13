import SwiftUI

struct MonthCalendar: View {
    @State private var month = Date()
    @State private var selected = Date()
    private var calendar: Calendar { .autoupdatingCurrent }
    private var start: Date { calendar.dateInterval(of: .month, for: month)!.start }
    private var offset: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: month)!.count }
    private var weekdays: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        return (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7] }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 24) }.accessibilityLabel("Previous month")
                Button("Today") { month = Date(); selected = month }.font(.system(size: 11)).foregroundStyle(.mint)
                Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 24) }.accessibilityLabel("Next month")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdays[index]).font(.system(size: 10, weight: .medium)).foregroundStyle(.gray)
                }
                ForEach(0..<(offset + count), id: \.self) { index in
                    if index < offset {
                        Color.clear.frame(height: 27)
                    } else {
                        let date = calendar.date(byAdding: .day, value: index - offset, to: start)!
                        let chosen = calendar.isDate(date, inSameDayAs: selected)
                        let today = calendar.isDateInToday(date)
                        Button { selected = date } label: {
                            Text("\(index - offset + 1)")
                                .font(.system(size: 12, weight: today ? .bold : .regular))
                                .foregroundStyle(chosen ? Color.black : (today ? .mint : .white))
                                .frame(maxWidth: .infinity).frame(height: 27)
                                .background(chosen ? Color.mint : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .overlay(RoundedRectangle(cornerRadius: 7).stroke(today ? Color.mint : .clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            Text(selected.formatted(date: .complete, time: .omitted))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.mint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func move(_ amount: Int) {
        if let next = calendar.date(byAdding: .month, value: amount, to: start) { month = next }
    }
}
