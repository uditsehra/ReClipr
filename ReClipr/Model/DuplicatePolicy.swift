//
//  DuplicatePolicy.swift
//  ReClipr
//
//  Created by Udit Sehra on 21/12/25.
//

import Foundation

enum DuplicatePolicy: String, CaseIterable, Codable{
    case none
    case timed
    case always
}
