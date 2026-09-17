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
                    title: "Backup Completed",
                    description: "System database successfully backed up to AWS S3 storage cloud.",
                    systemImage: "checkmark.icloud.fill",
                    tintColor: .green
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-3600),
                    title: "Security Alert",
                    description: "Failed login attempt detected from an unrecognized IP address in Germany.",
                    systemImage: "exclamationmark.triangle.fill",
                    tintColor: .red
                ),
                LogEvent(
                    timestamp: Date().addingTimeInterval(-7200),
                    title: "Update Installed",
                    description: "App version 2.4.1 patch was downloaded and installed automatically.",
                    systemImage: "arrow.down.circle.fill",
                    tintColor: .blue
                )
            ],
            eventCounts: [
                "syncAchieved": 12,
                "lot": 86,
                "stationName": 3,
                "ber": 245,
                "mer": 245
            ]
        )
        .navigationTitle("Activity Log")
    }
}
