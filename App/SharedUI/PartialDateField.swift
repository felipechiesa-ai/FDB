import SwiftUI
import FDBDomain

/// Edits an optional date at the precision the user knows. Missing parts are never filled in.
struct PartialDateField: View {
    let title: LocalizedStringKey
    @Binding var value: PartialDate?

    @State private var precision: Precision
    @State private var year: Int
    @State private var month: Int
    @State private var day: Int

    private enum Precision: String, CaseIterable, Identifiable {
        case unknown, year, month, day

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .unknown: "Unknown"
            case .year: "Year"
            case .month: "Month"
            case .day: "Day"
            }
        }
    }

    init(title: LocalizedStringKey, value: Binding<PartialDate?>) {
        self.title = title
        _value = value
        let current = value.wrappedValue
        _precision = State(initialValue: Self.precision(of: current))
        _year = State(initialValue: current?.year ?? Calendar.current.component(.year, from: Date()))
        _month = State(initialValue: current?.month ?? 1)
        _day = State(initialValue: current?.day ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(title, selection: $precision) {
                ForEach(Precision.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if precision != .unknown {
                HStack(spacing: 12) {
                    TextField("Year", value: $year, format: .number.grouping(.never))
                        .frame(width: 90)
                    if precision == .month || precision == .day {
                        Picker("Month", selection: $month) {
                            ForEach(1...12, id: \.self) { number in
                                Text(Calendar.current.monthSymbols[number - 1]).tag(number)
                            }
                        }
                    }
                    if precision == .day {
                        Picker("Day", selection: $day) {
                            ForEach(1...daysInMonth, id: \.self) { number in
                                Text("\(number)").tag(number)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: precision) { _, _ in commit() }
        .onChange(of: year) { _, _ in commit() }
        .onChange(of: month) { _, _ in
            day = min(day, daysInMonth)
            commit()
        }
        .onChange(of: day) { _, _ in commit() }
    }

    private var daysInMonth: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: firstDay) else {
            return 31
        }
        return range.count
    }

    private func commit() {
        switch precision {
        case .unknown: value = nil
        case .year: value = PartialDate(year: year)
        case .month: value = PartialDate(year: year, month: month)
        case .day: value = PartialDate(year: year, month: month, day: min(day, daysInMonth))
        }
    }

    private static func precision(of date: PartialDate?) -> Precision {
        switch date?.precision {
        case nil: .unknown
        case .year?: .year
        case .month?: .month
        case .day?: .day
        }
    }
}
