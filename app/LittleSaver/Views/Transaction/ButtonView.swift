//
//  ButtonView.swift
//  LittleSaver
//
//  Created by Rafael Soh on 14/5/22.
//

import LittleSaverCore
import Combine
import Foundation
import Popovers
import SwiftUI

struct ButtonView: View {
    let number: Int
    let size: CGSize

    var body: some View {
        Text("\(number)")
            .font(.system(size: 34, weight: .regular, design: .rounded))
            .frame(width: size.width * 0.3, height: size.height * 0.22)
            .background(Color.SecondaryBackground)
            .foregroundColor(Color.PrimaryText)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
