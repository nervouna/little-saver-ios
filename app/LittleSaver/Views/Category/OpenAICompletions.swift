//
//  OpenAICompletions.swift
//  LittleSaver
//
//  Created by Rafael Soh on 10/5/22.
//

import LittleSaverCore
import Combine
import CoreHaptics
import Popovers
import SwiftUI
import UIKit

struct OpenAICompletionsResponse: Decodable {
    let id: String
    let choices: [OpenAICompletionsOptions]
}

struct OpenAICompletionsOptions: Decodable {
    let text: String
}
