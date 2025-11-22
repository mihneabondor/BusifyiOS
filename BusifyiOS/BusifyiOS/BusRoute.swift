//
//  BusRoute.swift
//  BusifyiOS
//
//  Created by Mihnea on 7/9/25.
//


import AppIntents

enum BusRoute: String, AppEnum {
    case route42 = "42"
    case route7A = "7A"
    case route12B = "12B"
    case route99 = "99"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bus Route")

    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .route42: DisplayRepresentation(title: "42"),
        .route7A: DisplayRepresentation(title: "7A"),
        .route12B: DisplayRepresentation(title: "12B"),
        .route99: DisplayRepresentation(title: "99")
    ]
}
