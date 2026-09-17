//
//  LogEvent.swift
//  TunedTwo
//
//  View for displaying log events.
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
                        .fill(Color(.systemGray))
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

    var body: some View {
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
}

#Preview("Activity Log") {
    NavigationStack {
        EventLogView(events: [
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
                tintColor: .red // usage-defined or .orange
            ),
            LogEvent(
                timestamp: Date().addingTimeInterval(-7200),
                title: "Update Installed",
                description: "App version 2.4.1 patch was downloaded and installed automatically.",
                systemImage: "arrow.down.circle.fill",
                tintColor: .blue
            )
        ])
        .navigationTitle("Activity Log")
    }
}
