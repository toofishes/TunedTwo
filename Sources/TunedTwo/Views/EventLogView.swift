//
//  EventLogView.swift
//  TunedTwo
//
//  View for displaying log events and event-count summaries.
//

import SwiftUI
import TunedTwoCore

struct LogEventRow: View {
    let event: LogEvent
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Image(systemName: event.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(event.tintColor)
                    .clipShape(Circle())

                if !isLast {
                    Rectangle()
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(event.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(event.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 24)
        }
    }
}

struct EventLogView: View {
    let events: [LogEvent]
    let eventCounts: [String: Int]

    private var sortedCounts: [(key: String, value: Int)] {
        eventCounts.sorted { $0.key < $1.key }
    }

    var body: some View {
        HSplitView {
            eventList
                .frame(minWidth: 240)

            eventCountsTable
                .frame(minWidth: 180)
        }
    }

    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    LogEventRow(
                        event: event,
                        isLast: index == events.count - 1
                    )
                }
            }
            .padding()
        }
    }

    private var eventCountsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Event")
                    .font(.caption.bold())
                Spacer()
                Text("Count")
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.15))

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedCounts.enumerated()), id: \.element.key) { index, entry in
                        HStack(spacing: 8) {
                            Text(entry.key)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(entry.value)")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(index % 2 == 0 ? Color.clear : Color.gray.opacity(0.08))
                    }
                }
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.separator, lineWidth: 0.5)
        )
        .padding([.top, .leading, .trailing], 12)
    }
}

#Preview("Activity Log") {
    NavigationStack {
        EventLogView(
            events: [
                LogEvent(
                    timestamp: Date(),
                    title: "Synchronized",
                    description: "Synchronized",
                    systemImage: "checkmark.icloud.fill",
                    tintColor: .blue
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-60),
                    title: "Station Name",
                    description: "KOSF",
                    systemImage: "checkmark.icloud.fill",
                    tintColor: .blue
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-120),
                    title: "LOT File",
                    description:
                        "ID: 42, File: traffic.png, Size: 12400, MIME: TTN STM Traffic (0xFF8422D7), Service: type=1 #0 KOSF (2 components), Component: data id=3 port=0 sdt=0 aas=0, Component MIME: TTN STM Traffic (0xFF8422D7)",
                    systemImage: "checkmark.icloud.fill",
                    tintColor: .blue
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-180),
                    title: "SIG",
                    description: "Services: #0 KOSF (2 components), #1 KOSF-HD2 (1 component)",
                    systemImage: "antenna.radiowaves.left.and.right",
                    tintColor: .purple
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-240),
                    title: "AGC",
                    description: "Gain 42.0 dB, Peak -12.5 dBFS, Final true",
                    systemImage: "chart.line.uptrend.xyaxis",
                    tintColor: .orange
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-300),
                    title: "Stream",
                    description: "Seq 7, Size 1024, Service #0 KOSF, Component TTN STM Traffic (0xFF8422D7)",
                    systemImage: "arrow.left.arrow.right.circle.fill",
                    tintColor: .blue
                ),
            ],
            eventCounts: [
                "syncAchieved": 1,
                "stationName": 1,
                "lot": 86,
                "sig": 4,
                "agc": 245,
                "stream": 120,
                "mer": 245,
            ]
        )
        .navigationTitle("Activity Log")
    }
}
