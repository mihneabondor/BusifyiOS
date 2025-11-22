import AppIntents

struct GetNextBusIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Bus"
    static var description = IntentDescription("Shows when the next bus arrives.")

    @Parameter(title: "Route Number")
    var route: BusRoute

    static var parameterSummary: some ParameterSummary {
        Summary("Get the next \(\.$route) bus")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let nextBusTime = await fetchNextBusTime(forRoute: route.rawValue)
        return .result(dialog: "The next \(route.rawValue) bus arrives at \(nextBusTime).")
    }

    private func fetchNextBusTime(forRoute route: String) async -> String {
        // Replace with real API call
        return "8:15 AM"
    }
}
