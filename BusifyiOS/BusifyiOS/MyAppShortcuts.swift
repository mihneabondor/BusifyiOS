//
//  MyAppShortcuts.swift
//  BusifyiOS
//
//  Created by Mihnea on 7/9/25.
//


import AppIntents

struct MyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetNextBusIntent(),
            phrases: [
                "When is the next \(\.$route) bus in \(.applicationName)",
                "Next \(\.$route) bus with \(.applicationName)",
                "When does the \(\.$route) bus come in \(.applicationName)",
                "What time is the \(\.$route) bus in \(.applicationName)",
                "Show me the next \(\.$route) bus in \(.applicationName)"
            ],
            shortTitle: "Next Bus",
            systemImageName: "bus"
        )
    }
}
