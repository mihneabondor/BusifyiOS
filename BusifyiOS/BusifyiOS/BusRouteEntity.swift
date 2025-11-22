import AppIntents

struct BusRouteEntity: AppEntity {
    var id: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Bus Route")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id) bus")
    }

    static var defaultQuery = BusRouteQuery()
}

struct BusRouteQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [BusRouteEntity] {
        return identifiers.map { BusRouteEntity(id: $0) }
    }

    func suggestedEntities() async throws -> [BusRouteEntity] {
        // Provide suggested bus routes to help Siri disambiguate
        return [
            BusRouteEntity(id: "42"),
            BusRouteEntity(id: "15"),
            BusRouteEntity(id: "7A"),
            BusRouteEntity(id: "99")
        ]
    }

    func entities(matching string: String) async throws -> [BusRouteEntity] {
        // Basic example: return a route if the string is numeric or matches a known route
        return [BusRouteEntity(id: string)]
    }
}

// Recommended: conform to EntityStringQuery to improve natural language matching
extension BusRouteQuery: EntityStringQuery {}
